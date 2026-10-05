import AuthenticationServices
import SwiftUI

/// System AutoFill entry point. Every request needs the vault unlocked (Touch ID or master password)
/// inside the extension; nothing is filled silently.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private let state = AutoFillState()

    override func loadView() {
        state.completePassword = { [weak self] user, password in
            self?.extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: user, password: password))
        }
        state.completeCode = { [weak self] code in
            self?.extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code))
        }
        state.cancel = { [weak self] in
            self?.extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain,
                                                                    code: ASExtensionError.userCanceled.rawValue))
        }
        let host = NSHostingView(rootView: AutoFillView(state: state))
        view = host
        preferredContentSize = NSSize(width: 440, height: 500)
    }

    // Password list for the current site.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        state.begin(mode: .password, services: serviceIdentifiers, preselect: nil)
    }

    // A QuickType suggestion was picked: show unlock, then fill that exact item.
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        let mode: AutoFillState.Mode = credentialRequest.type == .oneTimeCode ? .oneTimeCode : .password
        state.begin(mode: mode, services: [credentialRequest.credentialIdentity.serviceIdentifier],
                    preselect: credentialRequest.credentialIdentity.recordIdentifier)
    }

    // We never fill without the user present.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain,
                                                          code: ASExtensionError.userInteractionRequired.rawValue))
    }

    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        state.begin(mode: .oneTimeCode, services: serviceIdentifiers, preselect: nil)
    }
}
