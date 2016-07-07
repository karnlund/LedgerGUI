//
//  WindowController.swift
//  LedgerGUI
//
//  Created by Florian on 06/07/16.
//  Copyright © 2016 objc.io. All rights reserved.
//

import Cocoa


class LedgerWindowController: NSWindowController {
    var balanceViewController: BalanceViewController? {
        return contentViewController?.childViewControllers.flatMap( { $0 as? BalanceViewController }).first
    }

    var registerViewController: RegisterViewController? {
        return contentViewController?.childViewControllers.flatMap( { $0 as? RegisterViewController }).first
    }
}
