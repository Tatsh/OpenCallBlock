//
//  ViewController.swift
//  OpenCallBlock
//
//  Created by Chris Ballinger on 10/27/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

import UIKit
import CallDataKit
import PhoneNumberKit
import CocoaLumberjackSwift
import CallKit
import Contacts



class ViewController: UIViewController {
    
    // MARK: - Properties
    
    @IBOutlet weak var numberField: PhoneNumberTextField!
    @IBOutlet weak var prefixLabel: UILabel!
    @IBOutlet weak var extensionActiveLabel: UILabel!
    @IBOutlet weak var blockedLabel: UILabel!
    @IBOutlet weak var whitelistLabel: UILabel!
    @IBOutlet weak var extraBlockingSwitch: UISwitch!
    
    let numberKit = PhoneNumberKit()
    private let database = DatabaseManager.shared
    
    private var user: User? {
        get {
            return database.user
        }
        set {
            database.user = newValue
        }
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        numberField.delegate = self
        numberField.maxDigits = 10
        numberField.withPrefix = false
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        refreshExtensionState()
        refreshUserState(user)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    // MARK: - Data Refresh
    
    /// Check whether or not extension is active
    private func refreshExtensionState() {
        CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: Constants.CallDirectoryExtensionIdentifier) { (reloadError) in
            if let error = reloadError as? CXErrorCodeCallDirectoryManagerError {
                DDLogError("Error reloading CXCallDirectoryManager extension: \(error.localizedDescription) \"\(error.code)\"")
            } else {
                DDLogError("Reloaded CXCallDirectoryManager extension.")
            }
            CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: Constants.CallDirectoryExtensionIdentifier) { (status, statusError) in
                if let error = statusError {
                    DDLogError("Error getting status for CXCallDirectoryManager extension: \(error.localizedDescription)")
                } else {
                    DDLogError("Got status for CXCallDirectoryManager extension: \(status)")
                }
                DispatchQueue.main.async {
                    // show warning if enabled with error
                    if status != .disabled,
                        reloadError != nil || statusError != nil {
                        self.setExtensionLabelActive(nil)
                    } else {
                        self.setExtensionLabelActive(status == .enabled)
                    }
                }
            }
        }
    }
    
    /// true=working&enabled, false=user disabled, nil=error
    private func setExtensionLabelActive(_ active: Bool?) {
        guard let active = active else {
            self.extensionActiveLabel.text = "\(UIStrings.ExtensionActive): ⚠️"
            return
        }
        if active {
            self.extensionActiveLabel.text = "\(UIStrings.ExtensionActive): ✅"
        } else {
            self.extensionActiveLabel.text = "\(UIStrings.ExtensionActive): ❌"
        }
    }
    
    /// Refresh UI from User data
    private func refreshUserState(_ user: User?) {
        if let number = user?.me.rawNumber {
            numberField.text = "\(number)"
            refreshNpaNxx(numberString: "\(number)")
        } else {
            numberField.text = ""
        }
        whitelistLabel.text = "\(UIStrings.Whitelist): \(user?.whitelist.count ?? 0) \(UIStrings.Numbers)"
        blockedLabel.text = "\(UIStrings.Blocked): \(user?.blocklist.count ?? 0) \(UIStrings.Numbers)"
        extraBlockingSwitch.isOn = user?.extraBlocking ?? false
        refreshExtensionState()
    }
    
    /// Refreshes NPA-NXX field, optionally saving User data
    func refreshNpaNxx(numberString: String, shouldSave: Bool = false) {
        var _number: PhoneNumber? = nil
        do {
            _number = try numberKit.parse(numberString, withRegion: "us", ignoreType: true)
        } catch {
            //DDLogWarn("Bad number \(error)")
        }
        guard let number = _number,
            let npaNxx = number.npaNxxString else { return }
        
        // valid number found
        numberField.resignFirstResponder()
        prefixLabel.text = "\(UIStrings.NpaNxxPrefix): \(npaNxx)"
        
        if shouldSave {
            var user = self.user
            user?.me = Contact(phoneNumber: number)
            if user == nil {
                user = User(phoneNumber: number)
            }
            user?.extraBlocking = extraBlockingSwitch.isOn
            // TODO: move this
            user?.refreshBlocklist()
            if let user = user {
                self.user = user
            }
            refreshUserState(user)
        }
    }
    
    // MARK: - UI Actions

    
    @IBAction func refreshWhitelist(_ sender: Any) {
        guard var user = self.user else {
            DDLogError("Must create a user first")
            return
        }
        
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { (success, error) in
            if let error = error {
                DDLogError("Contacts permission error: \(error)")
                return
            }
            var whitelist: Set<Contact> = []
            do {
                let request = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor])
                try store.enumerateContacts(with: request, usingBlock: { (contact, stop) in
                    for number in contact.phoneNumbers {
                        do {
                            let numberString = number.value.stringValue
                            let phoneNumber = try self.numberKit.parse(numberString, withRegion: "us", ignoreType: true)
                            let contact = Contact(phoneNumber: phoneNumber)
                            whitelist.insert(contact)
                        } catch {
                            DDLogError("Error parsing phone number: \(error)")
                        }
                    }
                })
            } catch {
                DDLogError("Could not enumerate contacts \(error)")
            }
            user.whitelist = whitelist.sorted()
            user.refreshBlocklist()
            self.user = user
            DispatchQueue.main.async {
                self.refreshUserState(user)
            }
        }
    }
    
    @IBAction func extraBlockingValueChanged(_ sender: Any) {
        if var user = self.user {
            user.extraBlocking = extraBlockingSwitch.isOn
            user.refreshBlocklist()
            self.user = user
        }
        refreshUserState(self.user)
    }
    
    @IBAction func numberFieldEditingChanged(_ sender: Any) {
        guard let numberString = numberField.text else {
            return
        }
        refreshNpaNxx(numberString: numberString, shouldSave: true)
    }
    
    @IBAction func enableExtensionPressed(_ sender: Any) {
        // TODO: Show alert view explaining how to enable
        // Settings => Phone => Call Blocking & Identification => Enable OpenCallBlock
        refreshExtensionState()
    }
    

    
     // MARK: - Navigation
     
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Show List editor for white/block list
        guard let user = self.user,
            let listEditor = segue.destination as? ListEditorViewController,
            let identifier = segue.identifier,
            let listEditorSegue = ListEditorSegue(rawValue: identifier) else {
            return
        }
        listEditor.setupWithUser(user, editorType: listEditorSegue.editorType)
     }
}

// MARK: - Constants

private struct Constants {
    static let CallDirectoryExtensionIdentifier = "sh.tat.OpenCallBlock.CallDirectoryExtension"
    static let EditBlocklistSegue = "editBlocklist"
    static let EditWhitelistSegue = "editWhitelist"
}

private struct UIStrings {
    static let ExtensionActive = "Extension Active"
    static let NpaNxxPrefix = "NPA-NXX Prefix"
    static let Whitelist = "Whitelist"
    static let Blocked = "Blocked"
    static let Numbers = "numbers"
}

// MARK: - Extensions

extension ViewController: UITextFieldDelegate {
}

private extension PhoneNumber {
    /// Returns NPA-NXX prefix of US number e.g. 800-555-5555 returns 800-555
    var npaNxx: UInt64? {
        guard countryCode == 1 else { return nil }
        return nationalNumber/10_000
    }
    var npaNxxString: String? {
        guard let npaNxx = self.npaNxx else { return nil }
        return "\(npaNxx / 1000)-\(npaNxx % 1000)"
    }
}

extension CXErrorCodeCallDirectoryManagerError.Code: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "An unknown error occurred."
        case .noExtensionFound:
            return "The call directory manager could not find a corresponding app extension."
        case .loadingInterrupted:
            return "The call directory manager was interrupted while loading the app extension."
        case .entriesOutOfOrder:
            return "The entries in the call directory are out of order."
        case .duplicateEntries:
            return "There are duplicate entries in the call directory."
        case .maximumEntriesExceeded:
            return "There are too many entries in the call directory."
        case .extensionDisabled:
            return "The call directory extension isn’t enabled by the system."
        case .currentlyLoading:
            return "currentlyLoading"
        case .unexpectedIncrementalRemoval:
            return "expectedIncrementalRemoval"
        }
    }
}

