# Windows command execution

This Flutter project is developed in Android Studio on Windows. Keep command
output in the current IDE terminal or Codex's captured terminal.

- For every Codex `exec_command` invocation on Windows, use `tty: true` and
  `login: false`, including diagnostics and approved commands outside the
  sandbox. This uses a headless ConPTY console. In this environment the default
  pipe mode (`tty: false`) launches a separate console host and Windows Terminal
  window for each PowerShell invocation.
- Run commands directly. Do not use `start`, `cmd /c start`, `Start-Process`,
  detached shell launches, or new external terminals. Keep stdout and stderr
  visible in the captured terminal. Do not suppress errors to hide windows.
- If a command returns a running session ID, poll or send input to that same
  session with `write_stdin`. Do not launch a duplicate command while it runs.
  Use `functions.wait` only for a running `functions.exec` cell ID.
- Before `flutter run`, inspect existing Flutter run sessions and devices. Reuse
  the existing IDE run/debug session when possible; do not start a second run
  for the same project and device. Do not create duplicate Flutter daemons,
  Gradle builds, ADB servers, or emulators.
- Flutter and Dart batch launchers write to the SDK cache outside this workspace.
  If a command stalls or fails because of sandbox access, diagnose it and request
  the required approval instead of repeatedly relaunching it. Pre-existing Dart
  language-server, tooling-daemon, and DevTools processes are normal; do not stop
  them or claim they are a lock conflict without evidence.
- Preserve Android Studio, the emulator, Flutter, Gradle, and ADB. If a temporary
  Flutter verification run is needed, detach cleanly after verification so the
  app stays running. Do not kill unrelated processes to clean up terminals.
- Terminal-launch fixes belong in tooling and execution settings. Do not change
  application UI, authentication, Supabase configuration, or database logic to
  address console windows.
