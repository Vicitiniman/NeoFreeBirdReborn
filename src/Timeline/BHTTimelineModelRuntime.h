#import <Foundation/Foundation.h>

// The URT model lost its T1 prefix in X 12.40. Keep accepted shapes narrow
// when reading its Swift-backed object field; never read arbitrary bytes as id.
FOUNDATION_EXPORT Class BHTURTStatusItemViewModelClass(void);
FOUNDATION_EXPORT BOOL BHTIsURTStatusItemViewModel(id object);
