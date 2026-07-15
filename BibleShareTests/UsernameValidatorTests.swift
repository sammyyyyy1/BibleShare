import Testing
@testable import BibleShare

struct UsernameValidatorTests {
    @Test func acceptsValidNames() {
        #expect(UsernameValidator.isValidFormat("grace_h"))
        #expect(UsernameValidator.isValidFormat("abc"))
        #expect(UsernameValidator.isValidFormat("A1_b2_C3_d4_e5_f6_g7"))   // 20 chars
    }

    @Test func rejectsInvalidNames() {
        #expect(!UsernameValidator.isValidFormat("ab"))                    // too short
        #expect(!UsernameValidator.isValidFormat("this_name_is_far_too_long")) // >20
        #expect(!UsernameValidator.isValidFormat("bad name"))             // space
        #expect(!UsernameValidator.isValidFormat("nope!"))               // punctuation
        #expect(!UsernameValidator.isValidFormat(""))                    // empty
    }
}
