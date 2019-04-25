// Copyright (C) 2016-2017 Parrot Drones SAS
//
//    Redistribution and use in source and binary forms, with or without
//    modification, are permitted provided that the following conditions
//    are met:
//    * Redistributions of source code must retain the above copyright
//      notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above copyright
//      notice, this list of conditions and the following disclaimer in
//      the documentation and/or other materials provided with the
//      distribution.
//    * Neither the name of the Parrot Company nor the names
//      of its contributors may be used to endorse or promote products
//      derived from this software without specific prior written
//      permission.
//
//    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
//    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
//    PARROT COMPANY BE LIABLE FOR ANY DIRECT, INDIRECT,
//    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
//    OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
//    AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//    OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
//    OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
//    SUCH DAMAGE.

import UIKit
import GroundSdk

class GpsCell: InstrumentProviderContentCell {

    @IBOutlet weak var satellites: UILabel!
    @IBOutlet weak var latitude: UILabel!
    @IBOutlet weak var longitude: UILabel!
    @IBOutlet weak var altitude: UILabel!
    @IBOutlet weak var horizontalAccuracy: UILabel!
    @IBOutlet weak var verticalAccuracy: UILabel!
    private var gps: Ref<Gps>?

    override func set(instrumentProvider provider: InstrumentProvider) {
        super.set(instrumentProvider: provider)
        selectionStyle = .none
        gps = provider.getInstrument(Instruments.gps) { [unowned self] gps in
            if let gps = gps {
                self.satellites.text = "\(gps.fixed ? "Fixed " : "")\(gps.satelliteCount)"
                if let location = gps.lastKnownLocation {
                    self.latitude.text = "\(location.coordinate.latitude)"
                    self.longitude.text = "\(location.coordinate.longitude)"
                    self.altitude.text = "\(location.altitude)"
                    self.horizontalAccuracy.text = "\(location.horizontalAccuracy)"
                    self.verticalAccuracy.text = "\(location.verticalAccuracy)"
                } else {
                    self.latitude.text = ""
                    self.longitude.text = ""
                    self.altitude.text = ""
                    self.horizontalAccuracy.text = ""
                    self.verticalAccuracy.text = ""
                }
                self.show()
            } else {
                self.hide()
            }
        }
    }
}
