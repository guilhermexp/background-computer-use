@testable import BackgroundComputerUse
import Testing

struct TypeTextFastVerificationPolicyTests {
    @Test
    func exactSameElementValueAndSelectionSkipProjectionReread() {
        let expected = TypeTextExpectedOutcomeDTO(
            valuePreview: "hello",
            valueString: "hello",
            selectionRange: TypeTextSelectionRangeDTO(location: 5, length: 0)
        )
        let observed = TypeTextObservedStateDTO(
            valuePreview: "hello",
            valueString: "hello",
            length: 5,
            truncated: false,
            selectedTextRange: TypeTextSelectionRangeDTO(location: 5, length: 0),
            isFocused: true
        )

        #expect(TypeTextFastVerificationPolicy.canSkipProjectionReread(
            expected: expected,
            observed: observed
        ))
    }

    @Test
    func selectionMismatchStillRequiresProjectionReread() {
        let expected = TypeTextExpectedOutcomeDTO(
            valuePreview: "hello",
            valueString: "hello",
            selectionRange: TypeTextSelectionRangeDTO(location: 5, length: 0)
        )
        let observed = TypeTextObservedStateDTO(
            valuePreview: "hello",
            valueString: "hello",
            length: 5,
            truncated: false,
            selectedTextRange: TypeTextSelectionRangeDTO(location: 0, length: 0),
            isFocused: true
        )

        #expect(TypeTextFastVerificationPolicy.canSkipProjectionReread(
            expected: expected,
            observed: observed
        ) == false)
    }
}
