//
//  DiskMountController.swift
//  VirtualC64
//
//  Created by Dirk Hoffmann on 05.02.18.
//

import Foundation

class DiskMountController : UserDialogController {
    
    var disk: AnyDiskProxy!
    
    let bytesPerRow = 32
    var halftrack = 35    // Selected halftrack to display
    var sizeInBytes = 0   // Number of bytes in the selected halftrack
    var sizeInBits = 0    // Number of bits in the selected halftrack
    
    // Outlets
    @IBOutlet weak var icon: NSImageView!
    @IBOutlet weak var header: NSTextField!
    @IBOutlet weak var subheader: NSTextField!
    @IBOutlet weak var subsubheader: NSTextField!
    @IBOutlet weak var contents: NSTableView!
    @IBOutlet weak var trackinfo: NSTextField!
    @IBOutlet weak var trackSizeinfo: NSTextField!
    @IBOutlet weak var stepper: NSStepper!
    @IBOutlet weak var driveSelector: NSPopUpButton!
    
    override func showSheet(withParent controller: MyController,
                            completionHandler:(() -> Void)? = nil) {
        
        track()
        disk = controller.mydocument.attachment as? AnyDiskProxy
        super.showSheet(withParent: controller, completionHandler: completionHandler)
    }
    
    override public func awakeFromNib() {
 
        let numItems = disk.numberOfHalftracks()
  
        stepper.minValue = 1
        stepper.maxValue = Double(numItems)
        stepper.integerValue = halftrack
        
        // Configure directory window
        // directory.intercellSpacing = NSSize(width: 0, height: 0)
        
        // Set icon and title
        switch disk.type() {
            
        case G64_FILE:
            icon.image = NSImage.init(named: NSImage.Name(rawValue: "IconD64"))
            header.stringValue = "G64 Format"
            break;

        default:
            assert(false)
            break;
        }
        
        update()
    }
    
    func update() {
    
        let t = (halftrack / 2) + 1
        
        disk.selectHalftrack(halftrack)
        sizeInBytes = disk.sizeOfHalftrack()
        sizeInBits = sizeInBytes * 8
        trackSizeinfo.stringValue = String(format: "%d Bytes", sizeInBytes)
        
        if (halftrack % 2 == 0) {
            let info = String(format: "Contents of halftrack %d:", halftrack)
            trackinfo.stringValue = String(info)
        } else {
            let info = String(format: "Contents of halftrack %d (track %d):", halftrack, t)
            trackinfo.stringValue = String(info)
        }
        
        contents.reloadData()
    }
    
    // Action methods
    
    @IBAction func stepperAction(_ sender: Any!) {
        
        let sender = sender as! NSStepper
        halftrack = sender.integerValue
        update()
    }
    
    @IBAction func okAction(_ sender: Any!) {
        
        track()
        
        if driveSelector.selectedItem!.tag == 1 {
            parent.changeDisk(disk, drive: 1)
        } else {
            parent.changeDisk(disk, drive: 2)
        }
        
        parent.metalScreen.rotateBack()
        hideSheet()
    }
}

//
// NSTableView delegate and data source
//

extension DiskMountController : NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView,
                   willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        
        // let c = cell as! NSTextFieldCell
        // c.font = cbmfont
        // c.textColor = .red
    }
}


extension DiskMountController : NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        
        return sizeInBytes / bytesPerRow
    }
    
    func tableView(_ tableView: NSTableView,
                   objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        
        if (tableColumn?.identifier)!.rawValue == "addr" {
            
            let s = String(format:"$%04X", row * bytesPerRow)
            return s
        }
        
        if (tableColumn?.identifier)!.rawValue == "data" {
            
            disk.selectHalftrack(halftrack)
            disk.seekHalftrack(row * bytesPerRow)
            return disk.readHalftrackHex(bytesPerRow)
        }
        
        return "???"
    }
}

