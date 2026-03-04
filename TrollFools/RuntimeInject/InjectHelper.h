#import <Foundation/Foundation.h>

/// Injects a dylib (at dylibPath) into a running process whose name contains processNameSubstring.
/// Returns YES on success. Requires TrollStore entitlements (task_for_pid, etc.).
BOOL TrollTitanInjectDylibIntoProcess(NSString *processNameSubstring, NSString *dylibPath);
