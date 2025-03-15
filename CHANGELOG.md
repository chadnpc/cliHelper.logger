# changelog

## [3/15/2025] v0.1.0 - Initial Release

### Core Components
- [Logger] class with session management
- Thread-safe logging operations
- IDisposable implementation for resource cleanup
- Synchronized log session storage

### Appenders
- [ConsoleAppender] for colored terminal output
- [FileAppender] for persistent log storage
- Custom appender interface (ILoggerAppender)

### Log Types
- [LogEventType] enum with 5 severity levels
- [ILoggerEntry] interface for log entries
- Built-in [LoggerEntry] implementation
- Extensible entry type system

### Key Features
- UTC timestamping for all entries
- Automatic directory creation
- StreamWriter-based file handling
- Exception logging support
- Type accelerators for core classes

## Optimizations
- Synchronized collection handling
- Buffered stream writing
- Reduced memory footprint
- Thread-safe file operations
- Clean disposal patterns
