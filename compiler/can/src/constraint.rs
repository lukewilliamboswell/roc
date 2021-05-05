use crate::expected::{Expected, PExpected};
use roc_collections::all::{MutSet, SendMap};
use roc_module::symbol::Symbol;
use roc_region::all::{Located, Region};
use roc_types::types::{Category, PatternCategory, Type};
use roc_types::{subs::Variable, types::VariableDetail};

#[derive(Debug, Clone, PartialEq)]
pub enum Constraint {
    Eq(Type, Expected<Type>, Category, Region),
    Store(Type, Variable, &'static str, u32),
    Lookup(Symbol, Expected<Type>, Region),
    Pattern(Region, PatternCategory, Type, PExpected<Type>),
    True, // Used for things that always unify, e.g. blanks and runtime errors
    SaveTheEnvironment,
    Let(Box<LetConstraint>),
    And(Vec<Constraint>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct LetConstraint {
    pub rigid_vars: Vec<Variable>,
    pub flex_vars: Vec<Variable>,
    pub def_types: SendMap<Symbol, Located<Type>>,
    pub defs_constraint: Constraint,
    pub ret_constraint: Constraint,
}

// VALIDATE

#[derive(Default, Clone)]
struct Declared {
    pub rigid_vars: MutSet<Variable>,
    pub flex_vars: MutSet<Variable>,
}

impl Constraint {
    pub fn validate(&self) -> bool {
        let mut unbound = Default::default();

        validate_help(self, &Declared::default(), &mut unbound);

        if !unbound.type_variables.is_empty() {
            panic!("found unbound type variables {:?}", &unbound.type_variables);
        }

        if !unbound.lambda_set_variables.is_empty() {
            panic!(
                "found unbound lambda set variables {:?}",
                &unbound.lambda_set_variables
            );
        }

        if !unbound.recursion_variables.is_empty() {
            panic!(
                "found unbound recursion variables {:?}",
                &unbound.recursion_variables
            );
        }

        true
    }
}

fn subtract(declared: &Declared, detail: &VariableDetail, accum: &mut VariableDetail) {
    for var in &detail.type_variables {
        if !(declared.rigid_vars.contains(&var) || declared.flex_vars.contains(&var)) {
            accum.type_variables.insert(*var);
        }
    }

    // lambda set variables are always flex
    for var in &detail.lambda_set_variables {
        if declared.rigid_vars.contains(&var.into_inner()) {
            panic!("lambda set variable {:?} is declared as rigid", var);
        }

        if !declared.flex_vars.contains(&var.into_inner()) {
            accum.lambda_set_variables.insert(*var);
        }
    }

    // recursion vars should be always rigid
    for var in &detail.recursion_variables {
        if declared.flex_vars.contains(&var) {
            panic!("recursion variable {:?} is declared as flex", var);
        }

        if !declared.rigid_vars.contains(&var) {
            accum.recursion_variables.insert(*var);
        }
    }
}

fn validate_help(constraint: &Constraint, declared: &Declared, accum: &mut VariableDetail) {
    use Constraint::*;

    match constraint {
        True | SaveTheEnvironment | Lookup(_, _, _) => { /* nothing */ }
        Store(typ, var, _, _) => {
            subtract(declared, &typ.variables_detail(), accum);

            if !declared.flex_vars.contains(var) {
                accum.type_variables.insert(*var);
            }
        }
        Constraint::Eq(typ, expected, _, _) => {
            subtract(declared, &typ.variables_detail(), accum);
            subtract(declared, &expected.get_type_ref().variables_detail(), accum);
        }
        Constraint::Pattern(_, _, typ, expected) => {
            subtract(declared, &typ.variables_detail(), accum);
            subtract(declared, &expected.get_type_ref().variables_detail(), accum);
        }
        Constraint::Let(letcon) => {
            let mut declared = declared.clone();
            declared
                .rigid_vars
                .extend(letcon.rigid_vars.iter().copied());
            declared.flex_vars.extend(letcon.flex_vars.iter().copied());

            validate_help(&letcon.defs_constraint, &declared, accum);
            validate_help(&letcon.ret_constraint, &declared, accum);
        }
        Constraint::And(inner) => {
            for c in inner {
                validate_help(c, declared, accum);
            }
        }
    }
}
