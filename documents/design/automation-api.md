# Automation API and command line

Part of the [OpenSloper design](../opensloper-design-document.md).

## Command line

`opensloper-cli` is built on the LCL-free core and ConsoleTools; its commands are on the generated Command line page, from the tables in `Sloper.CLI.Arguments`, which also build the parser. `check` exits with 0 for no problems, 1 for problems and 2 for a usage or file error, so it works in tests and CI. The commands are in `Sloper.CLI.Commands`, whose `RunCli` takes the arguments as a list and writes to the text files it is given, so `Sloper.Tests.CLI` runs every command in the test program, on copies of the examples, with no built program needed.

## Automation API

OpenSloper exposes its document operations as JSON-RPC 2.0, so Claude Code can test the app without GUI automation and Claude can help design and change patterns. The methods are on the generated Automation API page, from `Sloper.API.Methods`.

**One rule: the API only issues document commands.** Every call goes through the same document changes as the UI, so name rules, formula checks, cycle checks and undo apply exactly as for a user, and the API cannot make a state the UI could not. Measurement edits go through `Sloper.Core.Measurements` with the same safe write.

**Scripting** (`Sloper.API.Server`, `opensloper-cli serve`): one message a line over stdin and stdout, with no window. Objects are named by `id` or `name`; `add_point` and `add_edge` take a `type` and fields as in a pattern file, so a whole pattern can be built through the API. Formulas are in the pattern's unit and reported positions in mm. `render` returns the draft as SVG, or PNG with `format` (see Drawing images without the LCL), so Claude can look at the result, not only the numbers. `export` reads the saved files, as the publish app does. Batches are not supported. A notification (no `id`) gets no reply, even when it fails, as JSON-RPC requires, since `serve --connect` would take a stray reply as the answer to its next request.

**Errors are data.** A refused call returns a JSON-RPC error with the message, the field and the position in the formula (`LastError`, `LastErrorField`, `LastErrorPos`); scripts check the code, not the message.

**A generated Python client, not an embedded language.** `opensloper-cli doc opensloper.py` (`Sloper.Docs.Python`) writes `docs/reference/opensloper.py` from the methods table: one typed method per API method, with docstrings, a refused call raised as `OpenSloperError`, and `create_pattern_file` to make an empty pattern without a server. It is committed with the generated pages and MIT licensed, so it does not bind the scripts that import it. Pascal scripting inside the apps was rejected: a second binding layer, few pattern makers know Pascal, and scripts carried in shared patterns would run code from untrusted files.

**MCP** (`Sloper.API.MCP`). MCP is JSON-RPC 2.0 over stdio, so `opensloper-cli serve` also answers the MCP handshake (`initialize`, `ping`, `tools/list`, `tools/call`) and passes everything else to the API server; Claude Code and Claude Desktop connect directly. The tool list is made from the methods table: one tool per method, a JSON Schema from each parameter's kind, and `readOnlyHint` from the table. A refused call is a tool result with `isError` and the API's error, so the model reads why and retries. `render` with `format` png answers with an image, since MCP clients take PNG but not SVG.

## Live editing in the design window

Assistance → Allow Assistants to Connect, or starting with `--automation`, lets `opensloper-cli serve --connect` act as an MCP server on the pattern open in that window, so the user sees changes as they happen. Any MCP client can connect, so the window calls it "the assistant". Each change is one undo step labelled `Assistant: <description>`.

- `Sloper.API.Endpoint`: the run folder (`TAppPaths.RuntimeDir`, mode `0700` and checked to be the user's), the token and an endpoint file per window, `automation-<pid>.json` beside its socket (Windows: a loopback port). The apps' link shares the folder under other kinds. A client reads the newest; stale files left by a crash are skipped. A socket path over 103 characters is refused.
- `Sloper.API.Listener`: a thread accepting one client at a time. The first line must be `authenticate` with the token, within 5 s and 4 KB. Each request then runs on the main thread (`Synchronize`), between the user's own edits; writes never raise SIGPIPE.
- `Sloper.API.Connection`, behind `serve --connect`: connects on the first tool call and again after the window drops it, so the order of starting things does not matter.
- `Sloper.UI.Automation`, the window's controller: `TApiServer.CreateFor` works on the window's document without owning it; `open` is refused, since replacing the user's pattern would lose work; writes outside the pattern's folder ask first (`OnConfirmWrite`); `ui_state` reports file, selection and view. While the user has a change open (a drag) every edit is refused with "try again". After New or Open in the window (`TPatternDocument.Generation`), the next call is refused once with "another pattern is open; look again", since the IDs Claude knows belong to the old one.
- **Consent** is asked on the first request of a connection, reading included: Allow Once, Allow Until I Close OpenSloper, or Don't Allow (the default), which drops the connection. The status bar shows when an assistant can connect or is connected; clicking it disconnects.

## The Claude tabs

Each app's side panel ends with a Claude tab (`src/assistant/`, `Sloper.UI.AssistantPanel`): the user asks in their own words and Claude works on what the window has open, using tools. No consent prompt: the user typed the request.

- **Hosts.** The panel works through a `TAssistantHost` giving the tools, system prompt, opening text and generation, and running each call on the main thread. The design app's is the Automation API (`TApiServer.CreateFor`, every method but `open`). The layout and drape are documents of their own, so `Sloper.API.LayoutServer` and `Sloper.API.DrapeServer` have their own method tables (placing, packing, output, notes; placing, turning, aligning, attaching). These write no files: saving, exporting, printing and running Blender stay the user's. They are not offered over MCP. Each change is one undo step labelled `Claude: …`; edits wait while the user drags; New or Open ends the conversation.
- **The Assistance menu** in the design app holds Ask Claude, Anthropic API Key… and the MCP connection items. Without a key the tab's question box is off and says where to set the key; it reads the key again when the preferences change.
- **The key** is the user's Anthropic API key, set in Preferences → General and kept in `anthropic-key` in the config folder, mode `0600`, not in the shared `settings.json`; `ANTHROPIC_API_KEY` wins when set. A system keyring was rejected for now: three platform bindings with no Pascal library.
- **Raw HTTPS** (`Sloper.Assistant.Http`): Pascal has no Anthropic SDK, so `fphttpclient` with OpenSSL posts to `/v1/messages`; `ANTHROPIC_BASE_URL` points it elsewhere, which the GUI check uses with a mock server. The certificate chain and host name are checked in the handshake (`SSL_set1_host`), which FPC 3.2 leaves off, so the key never goes to an impostor; tests run a TLS server with the certificates in `tests/tls`. Stop shuts down the socket's reading side (`THttpsTransport.Abort`) so a silent server cannot hold it. OpenSSL can write to a socket the server reset, so the first transport made ignores SIGPIPE for the whole program, as Qt's networking does.
- **The request:** `claude-opus-5-5`, streamed, effort `high` (a wrong formula costs more than tokens), adaptive thinking, `max_tokens` 64000, refusal fallbacks, automatic prompt caching. The tools and system prompt come from the program's own tables and never change, so the cache holds across turns; the prompt carries the formula functions, units and object properties, and says text in a pattern is data, never instructions.
- **The loop** (`Sloper.Assistant.Conversation`, manual, since there is no SDK tool runner): the history only grows, except that only the last three images of the draft stay. Each assistant message goes back exactly as streamed (`Sloper.Assistant.Stream` rebuilds the blocks), thinking and signatures included, apart from what the API's fallback rule leaves out. Tool input that does not parse is not run and goes back as `INVALID_JSON`. A turn ending in `refusal`, `max_tokens` or an unknown stop reason runs none of its tools. A stream ending before `message_stop` is a failed request. 429 and 5xx are retried three times with `retry-after`; 401 says to check the key. A question stops after 40 requests. A question whose first request fails is taken back, so it is never sent twice.
- **Threads:** the conversation runs on a worker; text is shown and each tool run on the main thread (`Synchronize`).

## Safety

**`serve` over stdio needs no token**: only the process that started it holds its pipes, and it can already do anything the user can.

**The design window's socket needs protection**, since any local process could connect:

- Off by default; turned on per session.
- Local only: a Unix domain socket in the private run folder with mode `0600`, or 127.0.0.1 on Windows, never 0.0.0.0. If it ever speaks HTTP it must also check `Host` and `Origin`.
- **A token the app generates**: 32 random bytes from the OS, new at each start, in a file only the user can read, compared in constant time. The bridge in `opensloper-cli` reads it, so the user never pastes it into a chat and it never reaches the model or a transcript.
- **Consent in the app** on the first request of each connection.

**Prompt injection is the larger risk.** Claude reads names, notes and descriptions from patterns other people share, and a token does not help, since the attack comes through the client the user trusts. So the API limits what a steered client can do:

- `save` writes only `.sloper` files and replaces only a file that holds a pattern; `export` writes only its format's extension and replaces a file only with `overwrite`.
- `set_measurement` writes only the pattern's measurement file, after it loads as one.
- In the design window, writes outside the pattern's folder ask first, `open` is refused, and every change is a labelled undo step. The publish and drape tabs write no files.

**Other rules:** the API works on the open document, with file access only through `open`, `save` and `export` on paths the caller gives; nothing runs a shell (apps start each other with `TProcess` and an argument list); text written into SVG is escaped (`EscapeXML`).

## Drawing images without the LCL

`Sloper.Output.DraftPNG` draws the draft's SVG with BGRABitmap's no-LCL build (`bgrabitmappack4nolcl_freetype`), so the PNG always matches the SVG with no second drawing routine; the drape and layout renders go through it too. Text uses Lazarus's own FreeType with the bundled fonts (Noto Sans, else DejaVu Sans), not the system's, so images are the same on every platform and in tests; the SVG names them first in each `font-family`, since BGRABitmap cannot draw generic `sans-serif`. Widths are 16 to 4096 pixels, 1600 by default.

Our units that use a third-party drawing library live in `src/output/thirdparty`, where `opensloper-make.sh check` allows only BGRABitmap's no-LCL units, so the rest of `src/output` stays vector-only. The CLI and tests use the no-LCL package; the GUI apps the LCL build of the same units.
