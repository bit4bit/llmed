<!--
#!environment llm_provider opencode
#!environment llm_provider_model opencode-go/glm-5.3-flash
#!environment output_file todo.ollmed
#!environment release 1
-->

# Dependencies

* Use only the target language's standard library, including its HTTP server facilities. No external packages, no package managers.
* The user interface uses Bootstrap as the CSS template: the HTML head includes exactly this stylesheet link: `https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css`. No other assets are downloaded or embedded.
* All state must survive between separate HTTP requests and server restarts.

# Storage

* Tasks are persisted in `todos.json` in the current working directory as a JSON array of objects. Every stored task object has EXACTLY these four keys, no more and no fewer: `id` (integer), `title` (string), `done` (boolean), `created_at` (ISO8601 UTC string, e.g. `2026-11-21T19:00:00Z`), captured when the task is created. `id` is an integer assigned when a task is created: one plus the highest existing `id`, starting at 1, and never changed afterwards. `done` is a boolean, `false` on creation.
* Persistence goes through the load and store functions defined by this context; the server never reads or writes `todos.json` anywhere else. Keep the file valid JSON after every write.
* When the file does not exist or is empty, behave as an empty list.

# Server and routes

* An HTTP server listens on 127.0.0.1 on the port from the `PORT` environment variable (default 4567).
* `GET /` returns status 200 with a complete HTML page: Bootstrap components are used (`container`, `card`, a `table` of tasks, a `badge` per task showing `done` or `pending`, `btn btn-primary` for create, `btn btn-danger` for delete). Every user-provided string is HTML-escaped before embedding, so injected markup is displayed as text.
* The page uses EXACTLY these Bootstrap classes, all of them present in the rendered HTML: `container`, `card`, `table`, `badge bg-success`, `badge bg-secondary`, `btn btn-primary`, `btn btn-danger`.
* The page contains a form with method POST action `/add` and a text input named `title` to create a task, and per task small forms with method POST action `/toggle` and `/delete`, each carrying the task `id` in a hidden input.
* `POST /add` reads the `title` form field, creates the task, and responds with status 303 redirecting to `/`. `POST /toggle` flips the `done` value of the task with the submitted `id`. `POST /delete` removes it. Both respond with status 303 to `/`. Unknown IDs respond 404 with a plain text body.
* Any other path responds 404 with a plain text body.
* Task display order is by `id`, ascending.

# Entry point

* When executed directly ($PROGRAM_NAME == __FILE__ or the target language's idiomatic equivalent), start the server and print one line containing `listening` and the port.
* Wrap execution: on StandardError print a line containing FAIL-FAST and the reason and exit 1. The server keeps running until interrupted.
