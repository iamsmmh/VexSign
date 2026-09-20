//
//  NavigationViewWrapper.swift
//  Stars
//
//  Created by VexSign TeamSign Team on 7.04.2025.
//

import SwiftUI

public struct NBNavigationView<Content>: View where Content: View {
	private var _title: String
	private var _mode: NavigationBarItem.TitleDisplayMode
	private var _content: Content
	private var _path: Binding<NavigationPath>?

	public init(
		_ title: String,
		displayMode: NavigationBarItem.TitleDisplayMode = .automatic,
		@ViewBuilder content: () -> Content
	) {
		self._title = title
		self._mode = displayMode
		self._content = content()
		self._path = nil
	}

	/// Path-aware — single NavigationStack with programmatic navigation, avoids double nav bars.
	public init(
		_ title: String,
		displayMode: NavigationBarItem.TitleDisplayMode = .automatic,
		path: Binding<NavigationPath>,
		@ViewBuilder content: () -> Content
	) {
		self._title = title
		self._mode = displayMode
		self._content = content()
		self._path = path
	}

	public var body: some View {
		Group {
			if let path = _path {
				NavigationStack(path: path) {
					_content
						.navigationTitle(_title)
						.navigationBarTitleDisplayMode(_mode)
				}
			} else {
				NavigationStack {
					_content
						.navigationTitle(_title)
						.navigationBarTitleDisplayMode(_mode)
				}
			}
		}
	}
}
