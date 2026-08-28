import Foundation

enum TypeTextFastVerificationPolicy {
    static func canSkipProjectionReread(
        expected: TypeTextExpectedOutcomeDTO?,
        observed: TypeTextObservedStateDTO
    ) -> Bool {
        guard let expected,
              let expectedValue = expected.valueString,
              observed.valueString == expectedValue
        else {
            return false
        }
        guard let expectedSelection = expected.selectionRange else {
            return true
        }
        return observed.selectedTextRange == expectedSelection
    }
}
