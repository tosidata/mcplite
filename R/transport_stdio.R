run_stdio_server <- function(state) {
  cv <- nanonext::cv()

  reader_socket <- nanonext::read_stdin()
  on.exit(nanonext::reap(reader_socket), add = TRUE)

  nanonext::pipe_notify(reader_socket, cv, remove = TRUE, flag = TRUE)
  client <- nanonext::recv_aio(reader_socket, mode = "string", cv = cv)

  while (nanonext::wait(cv)) {
    if (nanonext::unresolved(client)) {
      next
    }

    line <- client$data
    if (nanonext::is_error_value(line)) {
      break
    }

    handled <- handle_input_line(line, state)
    state <- handled$state

    if (!is.null(handled$response)) {
      nanonext::write_stdout(to_json(handled$response))
    }

    client <- nanonext::recv_aio(reader_socket, mode = "string", cv = cv)
  }

  invisible(NULL)
}
