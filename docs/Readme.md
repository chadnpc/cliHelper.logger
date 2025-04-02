<!-- docs -->

## Core Concepts

*   **Logger (`[Logger]`)**: The main object you interact with. It holds configuration (like `MinimumLevel`) and a list of appenders. **Crucially, it should be disposed of when done (`$logger.Dispose()`)**.
*   **Appenders (`[ILogAppender]`)**: Define *where* log messages go. This module includes:
    *   `[ConsoleAppender]`: Writes colored output to the PowerShell host.
    *   `[FileAppender]`: Writes formatted text to a specified file.
    *   `[JsonAppender]`: Writes JSON objects (one per line) to a specified file.
    You add instances of these to the logger's `$logger.Appenders` list.
*   **Severity Levels (`[LogEventType]`)**: Define the importance of a message (Debug, Information, Warning, Error, Fatal). The logger's `MinimumLevel` filters messages below that level.
*   **Dispose()**: Because appenders (especially file-based ones) hold resources like open file handles, you **must** call `$logger.Dispose()` when you are finished logging to ensure logs are flushed and files are closed properly. Use a `try...finally` block for safety.
