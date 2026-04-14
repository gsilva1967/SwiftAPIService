//
//  OIDCPresentationContext.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

@preconcurrency import AppAuth
import Foundation

#if canImport(UIKit)
import UIKit

/// The platform-specific type used to present the OIDC authorization browser.
/// On iOS this is a `UIViewController`.
public typealias OIDCPresentingContext = UIViewController

#elseif canImport(AppKit)
import AppKit

/// The platform-specific type used to present the OIDC authorization browser.
/// On macOS this is an `NSWindow`.
public typealias OIDCPresentingContext = NSWindow
#endif

/// A protocol that the consuming application implements to provide
/// the UI anchor needed for the OIDC authorization browser session.
///
/// ```swift
/// class MyPresentationProvider: OIDCPresentationContextProviding {
///     @MainActor func presentingContext() -> OIDCPresentingContext {
///         // Return the key window's root view controller (iOS)
///         // or the key window (macOS).
///     }
/// }
/// ```
@MainActor
public protocol OIDCPresentationContextProviding: Sendable {
    /// Returns the platform-appropriate context for presenting the
    /// authorization browser session.
    func presentingContext() -> OIDCPresentingContext
}

// MARK: - Internal helpers

/// Creates an AppAuth external user agent from the platform-specific
/// presenting context.
///
/// - Parameters:
///   - context: The platform-specific anchor (view controller / window).
///   - prefersEphemeralSession: Whether to use an ephemeral browser session.
/// - Returns: An `OIDExternalUserAgent` ready for use with AppAuth, if one can be created.
@MainActor
func makeExternalUserAgent(
    from context: OIDCPresentingContext,
    prefersEphemeralSession: Bool
) -> OIDExternalUserAgent? {
    #if canImport(UIKit)
    return OIDExternalUserAgentIOS(
        presenting: context,
        prefersEphemeralSession: prefersEphemeralSession
    )
    #elseif canImport(AppKit)
    return OIDExternalUserAgentMac(presenting: context)
    #endif
}
