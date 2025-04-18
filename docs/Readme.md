<!-- docs -->

## Core Concepts

*   **Logger (`[Logger]`)**: The main object you interact with. It holds configuration (like `MinLevel`) and a list of appenders. **Crucially, it should be disposed of when done (`$logger.Dispose()`)**.
*   **Appenders (`[LogAppender]`)**: Define *where* log messages go. This module includes:
    *   `[ConsoleAppender]`: Writes colored output to the PowerShell host.
    *   `[FileAppender]`: Writes formatted text to a specified file.
    *   `[JsonAppender]`: Writes JSON objects (one per line) to a specified file.
    You add instances of these to the logger's `$logger._appenders` list.
*   **Severity Levels (`[LogLevel]`)**: Define the importance of a message (Debug, Info, Warn, Error, Fatal). The logger's `MinLevel` filters messages below that level.
*   **Dispose()**: Because appenders (especially file-based ones) hold resources like open file handles, you **must** call `$logger.Dispose()` when you are finished logging to ensure logs are flushed and files are closed properly. Use a `try...finally` block for safety.
