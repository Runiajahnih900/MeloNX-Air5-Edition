//
//  EnableJIT.swift
//  MeloNX
//
//  Created by Stossy11 on 10/02/2025.
//

import Foundation
import Network
import UIKit

func stikJITorStikDebug() -> Int {
    let teamid = SecTaskCopyTeamIdentifier(SecTaskCreateFromSelf(nil)!, nil)
    
    if checkifappinstalled("com.stik.sj") {
        return 1 // StikDebug
    }
    
    if checkifappinstalled("com.stik.sj.\(String(teamid ?? ""))") {
        return 2 // StikJIT
    }
    
    return 0 // Not Found
}

func checkforOld() -> Bool {
    let teamid = SecTaskCopyTeamIdentifier(SecTaskCreateFromSelf(nil)!, nil)
    
    if checkifappinstalled(changeAppUI("Y29tLnN0b3NzeTExLlBvbWVsbw==") ?? "") {
        return true
    }
    
    if checkifappinstalled(changeAppUI("Y29tLnN0b3NzeTExLlBvbWVsbw==") ?? "" + ".\(String(teamid ?? ""))") {
        return true
    }
    
    if checkifappinstalled((Bundle.main.bundleIdentifier ?? "").replacingOccurrences(of: "MeloNX", with: changeAppUI("UG9tZWxv") ?? "")) {
        return true
    }
    
    return false
}


func checkifappinstalled(_ id: String) -> Bool {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY) else {
        return false
    }
    
    typealias SBSLaunchApplicationWithIdentifierFunc = @convention(c) (CFString, Bool) -> Int32
    guard let sym = dlsym(handle, "SBSLaunchApplicationWithIdentifier") else {
        if let error = dlerror() {
            print(String(cString: error))
        }
        dlclose(handle)
        return false
    }
    
    let bundleID: CFString = id as CFString
    let suspended: Bool = false
    

    let SBSLaunchApplicationWithIdentifier = unsafeBitCast(sym, to: SBSLaunchApplicationWithIdentifierFunc.self)
    let result = SBSLaunchApplicationWithIdentifier(bundleID, suspended)

    return result == 9
}

func enableJITStik() {
    if #available(iOS 19, *), ProcessInfo.processInfo.hasTXM {
        let urlScheme = "stikjit://script?data=ZnVuY3Rpb24gbGl0dGxlRW5kaWFuSGV4U3RyaW5nVG9OdW1iZXIoaGV4U3RyKSB7CiAgICBjb25zdCBieXRlcyA9IFtdOwogICAgZm9yIChsZXQgaSA9IDA7IGkgPCBoZXhTdHIubGVuZ3RoOyBpICs9IDIpIHsKICAgICAgICBieXRlcy5wdXNoKHBhcnNlSW50KGhleFN0ci5zdWJzdHIoaSwgMiksIDE2KSk7CiAgICB9CiAgICBsZXQgbnVtID0gMG47CiAgICBmb3IgKGxldCBpID0gNDsgaSA-PSAwOyBpLS0pIHsKICAgICAgICBudW0gPSAobnVtIDw8IDhuKSB8IEJpZ0ludChieXRlc1tpXSk7CiAgICB9CiAgICByZXR1cm4gbnVtOwp9CgpmdW5jdGlvbiBudW1iZXJUb0xpdHRsZUVuZGlhbkhleFN0cmluZyhudW0pIHsKICAgIGNvbnN0IGJ5dGVzID0gW107CiAgICBmb3IgKGxldCBpID0gMDsgaSA8IDU7IGkrKykgewogICAgICAgIGJ5dGVzLnB1c2goTnVtYmVyKG51bSAmIDB4RkZuKSk7CiAgICAgICAgbnVtID4-PSA4bjsKICAgIH0KICAgIHdoaWxlIChieXRlcy5sZW5ndGggPCA4KSB7CiAgICAgICAgYnl0ZXMucHVzaCgwKTsKICAgIH0KICAgIHJldHVybiBieXRlcy5tYXAoYiA9PiBiLnRvU3RyaW5nKDE2KS5wYWRTdGFydCgyLCAnMCcpKS5qb2luKCcnKTsKfQoKZnVuY3Rpb24gbGl0dGxlRW5kaWFuSGV4VG9VMzIoaGV4U3RyKSB7CiAgICByZXR1cm4gcGFyc2VJbnQoaGV4U3RyLm1hdGNoKC8uLi9nKS5yZXZlcnNlKCkuam9pbignJyksIDE2KTsKfQoKZnVuY3Rpb24gZXh0cmFjdEJya0ltbWVkaWF0ZSh1MzIpIHsKICAgIHJldHVybiAodTMyID4-IDUpICYgMHhGRkZGOwp9CgpmdW5jdGlvbiBhdHRhY2goYnJlYWtwb2ludGNvdW50KSB7CiAgICBsZXQgcGlkID0gZ2V0X3BpZCgpOwogICAgbG9nKGBwaWQgPSAke3BpZH1gKTsKICAgIGxldCBhdHRhY2hSZXNwb25zZSA9IHNlbmRfY29tbWFuZChgdkF0dGFjaDske3BpZC50b1N0cmluZygxNil9YCk7CiAgICBsb2coYGF0dGFjaF9yZXNwb25zZSA9ICR7YXR0YWNoUmVzcG9uc2V9YCk7CiAgICAKICAgIGxldCB2YWxpZEJyZWFrcG9pbnRzID0gMDsKICAgIGxldCB0b3RhbEJyZWFrcG9pbnRzID0gMDsKCiAgICB3aGlsZSAodmFsaWRCcmVha3BvaW50cyA8IGJyZWFrcG9pbnRjb3VudCkgewogICAgICAgIHRvdGFsQnJlYWtwb2ludHMrKzsKICAgICAgICBsb2coYEhhbmRsaW5nIGJyZWFrcG9pbnQgJHt0b3RhbEJyZWFrcG9pbnRzfSAobG9va2luZyBmb3IgdmFsaWQgYnJlYWtwb2ludCAke3ZhbGlkQnJlYWtwb2ludHMgKyAxfS8ke2JyZWFrcG9pbnRjb3VudH0pYCk7CiAgICAgICAgCiAgICAgICAgbGV0IGJya1Jlc3BvbnNlID0gc2VuZF9jb21tYW5kKGBjYCk7CiAgICAgICAgbG9nKGBicmtSZXNwb25zZSA9ICR7YnJrUmVzcG9uc2V9YCk7CiAgICAgICAgCiAgICAgICAgbGV0IHRpZE1hdGNoID0gL1RbMC05YS1mXSt0aHJlYWQ6KD88dGlkPlswLTlhLWZdKyk7Ly5leGVjKGJya1Jlc3BvbnNlKTsKICAgICAgICBsZXQgdGlkID0gdGlkTWF0Y2ggPyB0aWRNYXRjaC5ncm91cHNbJ3RpZCddIDogbnVsbDsKICAgICAgICBsZXQgcGNNYXRjaCA9IC8yMDooPzxyZWc-WzAtOWEtZl17MTZ9KTsvLmV4ZWMoYnJrUmVzcG9uc2UpOwogICAgICAgIGxldCBwYyA9IHBjTWF0Y2ggPyBwY01hdGNoLmdyb3Vwc1sncmVnJ10gOiBudWxsOwogICAgICAgIGxldCB4ME1hdGNoID0gLzAwOig_PHJlZz5bMC05YS1mXXsxNn0pOy8uZXhlYyhicmtSZXNwb25zZSk7CiAgICAgICAgbGV0IHgwID0geDBNYXRjaCA_IHgwTWF0Y2guZ3JvdXBzWydyZWcnXSA6IG51bGw7CiAgICAgICAgCiAgICAgICAgaWYgKCF0aWQgfHwgIXBjIHx8ICF4MCkgewogICAgICAgICAgICBsb2coYEZhaWxlZCB0byBleHRyYWN0IHJlZ2lzdGVyczogdGlkPSR7dGlkfSwgcGM9JHtwY30sIHgwPSR7eDB9YCk7CiAgICAgICAgICAgIGNvbnRpbnVlOwogICAgICAgIH0KICAgICAgICAKICAgICAgICBjb25zdCBwY051bSA9IGxpdHRsZUVuZGlhbkhleFN0cmluZ1RvTnVtYmVyKHBjKTsKICAgICAgICBjb25zdCB4ME51bSA9IGxpdHRsZUVuZGlhbkhleFN0cmluZ1RvTnVtYmVyKHgwKTsKICAgICAgICBsb2coYHRpZCA9ICR7dGlkfSwgcGMgPSAke3BjTnVtLnRvU3RyaW5nKDE2KX0sIHgwID0gJHt4ME51bS50b1N0cmluZygxNil9YCk7CiAgICAgICAgCiAgICAgICAgbGV0IGluc3RydWN0aW9uUmVzcG9uc2UgPSBzZW5kX2NvbW1hbmQoYG0ke3BjTnVtLnRvU3RyaW5nKDE2KX0sNGApOwogICAgICAgIGxvZyhgaW5zdHJ1Y3Rpb24gYXQgcGM6ICR7aW5zdHJ1Y3Rpb25SZXNwb25zZX1gKTsKICAgICAgICBsZXQgaW5zdHJVMzIgPSBsaXR0bGVFbmRpYW5IZXhUb1UzMihpbnN0cnVjdGlvblJlc3BvbnNlKTsKICAgICAgICBsZXQgYnJrSW1tZWRpYXRlID0gZXh0cmFjdEJya0ltbWVkaWF0ZShpbnN0clUzMik7CiAgICAgICAgbG9nKGBCUksgaW1tZWRpYXRlOiAweCR7YnJrSW1tZWRpYXRlLnRvU3RyaW5nKDE2KX0gKCR7YnJrSW1tZWRpYXRlfSlgKTsKICAgICAgICAKICAgICAgICBpZiAoYnJrSW1tZWRpYXRlICE9PSAweDY5KSB7CiAgICAgICAgICAgIGxvZyhgU2tpcHBpbmcgYnJlYWtwb2ludDogYnJrIGltbWVkaWF0ZSB3YXMgbm90IDB4NjkgKHdhcyAweCR7YnJrSW1tZWRpYXRlLnRvU3RyaW5nKDE2KX0pYCk7CiAgICAgICAgICAgIGNvbnRpbnVlOwogICAgICAgIH0KICAgICAgICAKICAgICAgICBsb2coYEJSSyBpbW1lZGlhdGUgbWF0Y2hlcyBleHBlY3RlZCB2YWx1ZSAweDY5IC0gcHJvY2Vzc2luZyB2YWxpZCBicmVha3BvaW50ICR7dmFsaWRCcmVha3BvaW50cyArIDF9LyR7YnJlYWtwb2ludGNvdW50fWApOwogICAgICAgIAogICAgICAgIGxldCByZXF1ZXN0UlhSZXNwb25zZSA9IHNlbmRfY29tbWFuZChgX00ke3gwTnVtLnRvU3RyaW5nKDE2KX0scnhgKTsKICAgICAgICBsb2coYHJlcXVlc3RSWFJlc3BvbnNlID0gJHtyZXF1ZXN0UlhSZXNwb25zZX1gKTsKICAgICAgICAKICAgICAgICBpZiAoIXJlcXVlc3RSWFJlc3BvbnNlIHx8IHJlcXVlc3RSWFJlc3BvbnNlLmxlbmd0aCA9PT0gMCkgewogICAgICAgICAgICBsb2coYEZhaWxlZCB0byBhbGxvY2F0ZSBSWCBtZW1vcnlgKTsKICAgICAgICAgICAgY29udGludWU7CiAgICAgICAgfQogICAgICAgIAogICAgICAgIGxldCBqaXRQYWdlQWRkcmVzcyA9IEJpZ0ludChgMHgke3JlcXVlc3RSWFJlc3BvbnNlfWApOwogICAgICAgIGxvZyhgQWxsb2NhdGVkIEpJVCBwYWdlIGF0IGFkZHJlc3M6IDB4JHtqaXRQYWdlQWRkcmVzcy50b1N0cmluZygxNil9YCk7CiAgICAgICAgCiAgICAgICAgbGV0IHByZXBhcmVKSVRQYWdlUmVzcG9uc2UgPSBwcmVwYXJlX21lbW9yeV9yZWdpb24oaml0UGFnZUFkZHJlc3MsIHgwTnVtKTsKICAgICAgICBsb2coYHByZXBhcmVKSVRQYWdlUmVzcG9uc2UgPSAke3ByZXBhcmVKSVRQYWdlUmVzcG9uc2V9YCk7CiAgICAgICAgCiAgICAgICAgbGV0IHB1dFgwUmVzcG9uc2UgPSBzZW5kX2NvbW1hbmQoYFAwPSR7bnVtYmVyVG9MaXR0bGVFbmRpYW5IZXhTdHJpbmcoaml0UGFnZUFkZHJlc3MpfTt0aHJlYWQ6JHt0aWR9O2ApOwogICAgICAgIGxvZyhgcHV0WDBSZXNwb25zZSA9ICR7cHV0WDBSZXNwb25zZX1gKTsKICAgICAgICAKICAgICAgICBsZXQgcGNQbHVzNCA9IG51bWJlclRvTGl0dGxlRW5kaWFuSGV4U3RyaW5nKHBjTnVtICsgNG4pOwogICAgICAgIGxldCBwY1BsdXM0UmVzcG9uc2UgPSBzZW5kX2NvbW1hbmQoYFAyMD0ke3BjUGx1czR9O3RocmVhZDoke3RpZH07YCk7CiAgICAgICAgbG9nKGBwY1BsdXM0UmVzcG9uc2UgPSAke3BjUGx1czRSZXNwb25zZX1gKTsKICAgICAgICAKICAgICAgICB2YWxpZEJyZWFrcG9pbnRzKys7CiAgICAgICAgbG9nKGBDb21wbGV0ZWQgdmFsaWQgYnJlYWtwb2ludCAke3ZhbGlkQnJlYWtwb2ludHN9LyR7YnJlYWtwb2ludGNvdW50fSAtIHJldHVybmluZyBhZGRyZXNzIDB4JHtqaXRQYWdlQWRkcmVzcy50b1N0cmluZygxNil9YCk7CiAgICB9CiAgICAKICAgIGxldCBkZXRhY2hSZXNwb25zZSA9IHNlbmRfY29tbWFuZChgRGApOwogICAgbG9nKGBkZXRhY2hSZXNwb25zZSA9ICR7ZGV0YWNoUmVzcG9uc2V9YCk7Cn0KCmF0dGFjaCgzKTsgLy8gTWVsb05YIHVzZXMgMyBicmVha3BvaW50cywgYWRqdXN0IGFzIG5lZWRlZC4&bundle-id=\(Bundle.main.bundleIdentifier ?? "wow")&force-pip=1"
        if let launchURL = URL(string: urlScheme), !isJITEnabled() {
            UIApplication.shared.open(launchURL, options: [:], completionHandler: nil)
        }
    } else {
        let urlScheme = "stikjit://enable-jit?bundle-id=\(Bundle.main.bundleIdentifier ?? "wow")"
        if let launchURL = URL(string: urlScheme), !isJITEnabled() {
            UIApplication.shared.open(launchURL, options: [:], completionHandler: nil)
        }
    }
}
