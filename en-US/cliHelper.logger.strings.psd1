@{
  ModuleName    = 'cliHelper.logger'
  ModuleVersion = '0.1.1'
  ReleaseNotes  = @'
# cliHelper.logger v0.1.1 Release Notes

## Initial Release Features

### Core Components
- [Logger] class with session management
- Thread-safe logging operations
- IDisposable implementation for resource cleanup
- Synchronized log session storage

### Appenders
- [ConsoleAppender] for colored terminal output
- [FileAppender] for persistent log storage

### Log Types
- [LogLevel] enum with 5 severity levels
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

'@
}