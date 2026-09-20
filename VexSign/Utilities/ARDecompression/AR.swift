//
//  SwiftAR.swift
//  SwiftAR
//
//  Created by nekohaxx on 8/18/24.
//

import Foundation

class AR: NSObject {
	private var _data: Data
	
	init(with url: URL) throws {
		self._data = try Data(contentsOf: url)
		super.init()
	}
	
	func extract() async throws -> [ARFileModel] {
		guard _data.count >= 8 else {
			throw ARError.badArchive("Archive too small")
		}
		if [UInt8](_data.subdata(in: Range(0...7))) != [0x21, 0x3c, 0x61, 0x72, 0x63, 0x68, 0x3e, 0x0a] {
			throw ARError.badArchive("Invalid magic")
		}
		
		let data = _data.subdata(in: 8..<_data.endIndex)
		
		var offset = 0
		var files: [ARFileModel] = []
		while offset + 60 <= data.count {
			let fileInfo = try _getFileInfo(data, offset)
			files.append(fileInfo)
			offset += fileInfo.size + 60
			offset += offset % 2
		}
		return files
	}
	
	private func _getFileInfo(_ data: Data, _ offset: Int) throws -> ARFileModel {
		guard offset + 60 <= data.count else {
			throw ARError.badArchive("Header truncated")
		}

		guard let sizeStr = String(data: data.subdata(in: offset+48..<offset+58), encoding: .ascii),
		      let size = Int(_removePadding(sizeStr)), size >= 0 else {
			throw ARError.badArchive("Invalid size")
		}

		guard offset + 60 + size <= data.count else {
			throw ARError.badArchive("File data truncated")
		}
		
		let rawName = String(data: data.subdata(in: offset..<offset+16), encoding: .ascii) ?? ""
		let name = _removePadding(rawName)
		guard !name.isEmpty else {
			throw ARError.badArchive("Invalid name")
		}

		let modDateStr = String(data: data.subdata(in: offset+16..<offset+28), encoding: .ascii) ?? "0"
		let modTimestamp = Double(_removePadding(modDateStr)) ?? 0
		let ownerStr = String(data: data.subdata(in: offset+28..<offset+34), encoding: .ascii) ?? "0"
		let ownerId = Int(_removePadding(ownerStr)) ?? 0
		let groupStr = String(data: data.subdata(in: offset+34..<offset+40), encoding: .ascii) ?? "0"
		let groupId = Int(_removePadding(groupStr)) ?? 0
		let modeStr = String(data: data.subdata(in: offset+40..<offset+48), encoding: .ascii) ?? "0"
		let mode = Int(_removePadding(modeStr)) ?? 0
		
		return ARFileModel(
			name: name,
			modificationDate: Date(timeIntervalSince1970: modTimestamp),
			ownerId: ownerId,
			groupId: groupId,
			mode: mode,
			size: size,
			content: data.subdata(in: offset+60..<offset+60+size)
		)
	}
	
	private func _removePadding(_ paddedString: String) -> String {
		paddedString.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

enum ARError: Error {
	case badArchive(String)
}
