#pragma once

#import <Foundation/Foundation.h>

// Temporary beta-only diagnostics. Arming is explicit and captures at most
// one standalone CreateTweet plus one reply CreateTweet. The ordinary
// compatibility diagnostics remain metadata-only; this module is included
// only by the explicit detailed-report export path.
void BHTArmDetailedReplyDiagnostics(void);
void BHTDisarmDetailedReplyDiagnostics(void);
BOOL BHTDetailedReplyDiagnosticsIsArmed(void);
BOOL BHTDetailedReplyDiagnosticsHasCapture(void);
void BHTClearDetailedReplyDiagnostics(void);

// Cheap lock-free hint for the app-global NSURLSession constructors. This is
// only an early-out; callers must also pass the body-blind exact request gate
// below before accessing request.HTTPBody.
BOOL BHTDetailedReplyDiagnosticsNetworkCaptureMayBeActive(void);

// Deadline-aware, body-blind gate for the exact HTTPS first-party POST
// CreateTweet operations. It never reads the body, headers, cookies, URL
// query, or identifiers. A false result forbids all request-body access.
BOOL BHTDetailedReplyDiagnosticsRequestIsEligible(
    NSURLRequest* _Nullable request);

// Called after X has created the task and before the request leaves the
// process. requestBody is either the task constructor's explicit upload data
// or request.HTTPBody; it is parsed transiently into a value-free schema. The
// request, body, URL, headers, identifiers, and account objects are never
// retained. replySessionGeneration is zero outside the native reply window.
void BHTDetailedReplyDiagnosticsCaptureRequest(
    NSURLRequest* _Nullable request,
    NSData* _Nullable requestBody,
    NSURLSessionTask* _Nullable task,
    NSString* constructorCategory,
    NSUInteger replySessionGeneration);

// Merges fixed transport categories into a request previously accepted by
// the paired capture. Raw responses and raw errors are not inspected.
void BHTDetailedReplyDiagnosticsCompleteRequest(
    NSURLSessionTask* _Nullable task,
    NSError* _Nullable error);

// Privacy-safe account-context correlation. Objects are held weakly and only
// pointer-equality availability/results are exported; no account property is
// read or retained.
void BHTDetailedReplyDiagnosticsNoteReplyAccount(id _Nullable account);
void BHTDetailedReplyDiagnosticsNoteCompatibilityAccount(
    id _Nullable account);

// Records only X's guarded TFNTwitterComposition -isReply boolean and the
// active native account object immediately before _t1_sendCompositions:.
// The account is held weakly; no property, identifier, or content is read.
void BHTDetailedReplyDiagnosticsNoteCompositionContext(
    BOOL isReply,
    id _Nullable activeAccount);

// Returns an opaque, non-personal epoch/kind token only for the currently
// armed composition and an exact eligible CreateTweet URL. The caller may
// associate it with X's original request object; it is never exported.
NSDictionary* _Nullable
BHTDetailedReplyDiagnosticsApplicationTokenForRequestURL(
    NSURL* _Nullable requestURL);

// Records that the exact X 12.9 original-request association hook passed its
// runtime ABI checks. This is availability metadata only.
void BHTDetailedReplyDiagnosticsSetApplicationBindingHookAvailable(
    BOOL available);

// Token-bound application checkpoints. Unlike the legacy reply-window path,
// these never synthesize an attempt and can safely record the standalone
// control as well as the reply.
void BHTDetailedReplyDiagnosticsCaptureBoundDecodedResponse(
    NSDictionary* _Nullable applicationToken,
    id _Nullable response,
    id _Nullable model,
    id _Nullable parseError,
    id _Nullable APIErrors);
void BHTDetailedReplyDiagnosticsCaptureBoundPreparedResponse(
    NSDictionary* _Nullable applicationToken,
    BOOL observationComplete,
    id _Nullable effectiveModel,
    id _Nullable effectiveParseError,
    id _Nullable effectiveOperationError,
    id _Nullable effectiveAPIErrors,
    id _Nullable finalModel,
    id _Nullable finalParseError,
    id _Nullable finalOperationError,
    id _Nullable finalAPIErrors);

// Called only after the existing X 12.9 active-reply and exact first-party
// CreateTweet URL gates have accepted the response. The response's decoded
// JSON data is bounded and recursively redacted before it is retained.
void BHTDetailedReplyDiagnosticsCaptureDecodedResponse(
    NSUInteger sessionGeneration,
    id _Nullable response,
    id _Nullable model,
    id _Nullable parseError,
    id _Nullable APIErrors);

void BHTDetailedReplyDiagnosticsCapturePreparedResponse(
    NSUInteger sessionGeneration,
    BOOL observationComplete,
    id _Nullable effectiveModel,
    id _Nullable effectiveParseError,
    id _Nullable effectiveOperationError,
    id _Nullable effectiveAPIErrors,
    id _Nullable finalModel,
    id _Nullable finalParseError,
    id _Nullable finalOperationError,
    id _Nullable finalAPIErrors);

void BHTDetailedReplyDiagnosticsCaptureFailure(
    NSUInteger sessionGeneration,
    NSString* source,
    NSNotification* _Nullable notification);

// Captures the exact Objective-C status/error pair at X's typed
// update-status completion seam. This avoids touching the generic Swift ABI.
void BHTDetailedReplyDiagnosticsCaptureTypedResult(
    NSUInteger sessionGeneration,
    NSString* stage,
    id _Nullable status,
    id _Nullable error);

NSDictionary* BHTDetailedReplyDiagnosticSnapshot(void);
