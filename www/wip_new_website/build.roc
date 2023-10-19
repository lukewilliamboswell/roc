#!/usr/bin/env roc
app "website-builder"
    packages { pf: "https://github.com/roc-lang/basic-cli/releases/download/0.5.0/Cufzl36_SnJ4QbOoEmiJ5dIpUxBvdB3NEySvuH82Wio.tar.br" }
    imports [
        pf.Task.{ Task },
        pf.Cmd,
    ]
    provides [main] to pf

main = 
    # TODO take dist folder name and main.roc path as args once https://github.com/roc-lang/basic-cli/issues/82 is fixed
    # TODO add function to remove boilerplate
    # Remove dist folder
    {} <- 
        Cmd.new "rm"
        |> Cmd.args ["-rf", "dist/"]
        |> Cmd.status
        |> Task.onErr \_ -> crash "Failed to remove dist folder"
        |> Task.await

    # Build site
    {} <- 
        Cmd.new "roc"
        |> Cmd.args ["run", "main.roc", "--", "content/", "dist/wip/"]
        |> Cmd.status
        |> Task.onErr \_ -> crash "Failed to build site"
        |> Task.await

    # Copy static files
    # TODO figure out why we can't copy the whole folder here
    # works when doing one file at a time
    # Must be related to the implementation of Cmd in basic-cli
    # Use a bash script as a workaround
    {} <- 
        Cmd.new "bash"
        |> Cmd.args ["copy-static.sh"]
        |> Cmd.status
        |> Task.onErr \_ -> crash "Failed to copy static files"
        |> Task.await

    # Download the repl nightly and copy to dist
    {} <- 
        Cmd.new "bash"
        |> Cmd.args ["download-repl.sh"]
        |> Cmd.status
        |> Task.onErr \_ -> crash "Failed to copy static files"
        |> Task.await

    # Copy font files - assume that www/build.sh has been run previously and the
    # fonts are available locally in ../build/fonts
    {} <- 
        Cmd.new "cp"
        |> Cmd.args ["-r", "../build/fonts/", "dist/fonts/"]
        |> Cmd.status
        |> Task.onErr \_ -> crash "Failed to copy static files"
        |> Task.await

    # Start file server
    {} <- 
        Cmd.new "simple-http-server"
        |> Cmd.args ["-p", "8080", "--nocache", "--index", "--", "dist/"]
        |> Cmd.status
        |> Task.onErr \_ -> crash "Failed to run file server; consider intalling with `cargo install simple-http-server`"
        |> Task.await

    Task.ok {}
