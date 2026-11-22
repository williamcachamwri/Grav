//
//  GravOnboardingChrome.swift
//  Grav
//
//  Header section overline, squircle close button, and footer escape keycap hint,
//  ported 1:1 from Snapzy's `SnapzyOnboardingChrome.swift`.
//

import AppKit
import SwiftUI

// MARK: - Section Label

struct GravOnboardingOverline: View {
    var text: String
    var tint: Color = GravGlassInk.muted
    var rule: Bool = false

    init(_ text: String, tint: Color = GravGlassInk.muted, rule: Bool = false) {
        self.text = text
        self.tint = tint
        self.rule = rule
    }

    var body: some View {
        HStack(spacing: GravSpace.md) {
            if rule {
                Rectangle()
                    .fill(tint.opacity(0.55))
                    .frame(width: 12, height: 0.5)
            }

            Text(text)
                .font(.system(size: GravOnboardingType.sectionLabel, weight: .semibold))
                .tracking(GravOnboardingType.sectionTracking)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Close Button

struct GravOnboardingCloseButton: View {
    var action: () -> Void

    @State private var isHovered = false

    private var shape: RoundedRectangle {
        Radius.controlRect(forHeight: ControlMetrics.toolbarButton)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? GravGlassInk.primary : GravGlassInk.muted)
                .frame(width: ControlMetrics.toolbarButton, height: ControlMetrics.toolbarButton)
                .background(
                    shape
                        .fill(isHovered ? GravGlassInk.fillHover : GravGlassInk.fillRaised)
                        .overlay(
                            shape.strokeBorder(
                                isHovered ? GravGlassInk.hairlineStrong : GravGlassInk.hairline,
                                lineWidth: GravSurfaceGlass.specularLineWidth
                            )
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GravMotionPreferences.shared.spec(.hover).animation) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("Close Onboarding")
    }
}

// MARK: - Escape Hint

struct GravOnboardingEscapeHint: View {
    var text: String

    var body: some View {
        HStack(spacing: GravSpace.md) {
            GravKeycapChip(label: "esc")
            ZStack(alignment: .leading) {
                Text(text)
                    .font(.system(size: GravOnboardingType.caption))
                    .foregroundStyle(GravGlassInk.muted)
                    .id(text)
                    .transition(.opacity)
            }
        }
    }
}
