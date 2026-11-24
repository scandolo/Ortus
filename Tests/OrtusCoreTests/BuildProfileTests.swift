import OrtusCore

struct BuildProfileTests {
    func developerModeIsPreviewOnly() {
        expect(BuildProfile.developerMode(stored: true, isPreview: true))
        expect(!BuildProfile.developerMode(stored: false, isPreview: true))
        // A release never shows developer tools, even with the setting saved from before.
        expect(!BuildProfile.developerMode(stored: true, isPreview: false))
        expect(!BuildProfile.developerMode(stored: false, isPreview: false))
    }
}
