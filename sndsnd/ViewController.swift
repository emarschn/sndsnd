//
//  ViewController.swift
//  sndsnd
//
//  Created by Eric Marschner on 1/15/19.
//  Copyright © 2019 Eric Marschner. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation
import AudioToolbox
import Accelerate

class ViewController: UIViewController {

    @IBOutlet weak var wave0: WaveformView!
    @IBOutlet weak var wave1: WaveformView!

    @IBOutlet weak var channelsLabel: UILabel!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var inputLabel: UILabel!

    var audioEngine : AVAudioEngine!
    var mixer : AVAudioMixerNode!
    var recording = false

    private var averagePowerForChannel0: Float = 0
    private var averagePowerForChannel1: Float = 0
    let LEVEL_LOWPASS_TRIG:Float32 = 0.30

    override func viewDidLoad() {
        super.viewDidLoad()

        setupAudio()
        setupView()
        setupNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if AVCaptureDevice.authorizationStatus(for: AVMediaType.audio) != .authorized {
            AVCaptureDevice.requestAccess(for: AVMediaType.audio,
                                          completionHandler: { (granted: Bool) in
            })
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func setupAudio() {
        self.audioEngine = AVAudioEngine()
        self.mixer = AVAudioMixerNode()
        self.audioEngine.attach(mixer)
    }

    func setupView() {
        self.inputLabel.text = ""
        self.channelsLabel.text = ""

        let routePickerView = AVRoutePickerView(frame: .init(x: 0, y: 0, width: 40, height: 40))
        let but = UIBarButtonItem.init(customView: routePickerView)
        self.navigationItem.rightBarButtonItem = but

        let displayLink = CADisplayLink(target: self, selector: #selector(updateMeters))
        displayLink.add(to: RunLoop.current, forMode: RunLoop.Mode.common)
    }

    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChangeListener(notification:)), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    func startPassThru() {
        self.recording = true

        let options: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP, .allowBluetooth]
        try! AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.default, policy: .default, options: options)
        try! AVAudioSession.sharedInstance().setActive(true)

        let sampleRate = AVAudioSession.sharedInstance().sampleRate

        let inputNode = self.audioEngine.inputNode
        let inFormat = inputNode.inputFormat(forBus: 0)

        self.channelsLabel.text = "Channels: \(inFormat.channelCount)"

        self.audioEngine.connect(inputNode, to: self.mixer, format: inFormat)
        self.audioEngine.connect(self.mixer, to: self.audioEngine.mainMixerNode, format: inFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inFormat) {[weak self] (buffer:AVAudioPCMBuffer, when:AVAudioTime) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.audioMetering(buffer: buffer)
        }

        self.mixer.installTap(onBus: 0, bufferSize: AVAudioFrameCount(sampleRate * 0.4), format: inFormat, block: { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) -> Void in

        })

        try! self.audioEngine.start()

        UIApplication.shared.isIdleTimerDisabled = true

        checkRoutes()
    }

    func stopPassThru() {
        self.inputLabel.text = ""
        self.channelsLabel.text = ""
        self.recording = false
        self.audioEngine.stop()
        self.mixer.removeTap(onBus: 0)
        try! AVAudioSession.sharedInstance().setActive(false)

        UIApplication.shared.isIdleTimerDisabled = false
    }

    @objc func updateMeters() {
        wave0.updateWithLevel(CGFloat(pow(10, self.averagePowerForChannel0 / 20)))
        wave1.updateWithLevel(CGFloat(pow(10, self.averagePowerForChannel1 / 20)))
    }

    func completion() {
        if self.recording {
            DispatchQueue.main.async {
                self.rec(UIButton())
            }
        }
    }

    @IBAction func rec(_ sender: Any) {
        if self.recording {
            self.stopPassThru()
            self.startButton.setTitle("START", for: .normal)
        } else {
            self.startPassThru()
            self.startButton.setTitle("STOP", for: .normal)
        }
    }

    @objc private func audioRouteChangeListener(notification: Notification) {
        /*let rawReason = notification.userInfo![AVAudioSessionRouteChangeReasonKey] as! UInt
        let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)!
        switch reason {
        case .newDeviceAvailable:
            print("headphone plugged in")
        case .oldDeviceUnavailable:
            print("headphone pulled out")
        default:
            break
        }*/
        DispatchQueue.main.async {
            self.checkRoutes()
        }
    }

    func checkRoutes() {
        inputLabel.isHidden = true
        let route = AVAudioSession.sharedInstance().currentRoute
        for port in route.inputs {
            if port.portType == AVAudioSession.Port.lineIn {
                inputLabel.text = "Line-In"
                inputLabel.isHidden = false
            } else if port.portType == AVAudioSession.Port.headsetMic {
                inputLabel.text = "Headset Mic"
                inputLabel.isHidden = false
            } else if port.portType == AVAudioSession.Port.builtInMic {
                inputLabel.text = "Device"
                inputLabel.isHidden = false
            }
        }
    }

    // https://stackoverflow.com/questions/30641439/level-metering-with-avaudioengine/30651552
    private func audioMetering(buffer:AVAudioPCMBuffer) {
        buffer.frameLength = 1024
        let inNumberFrames:UInt = UInt(buffer.frameLength)
        if buffer.format.channelCount > 0 {
            let samples = (buffer.floatChannelData![0])
            var avgValue:Float32 = 0
            vDSP_meamgv(samples,1 , &avgValue, inNumberFrames)
            var v:Float = -100
            if avgValue != 0 {
                v = 20.0 * log10f(avgValue)
            }
            self.averagePowerForChannel0 = (self.LEVEL_LOWPASS_TRIG*v) + ((1-self.LEVEL_LOWPASS_TRIG)*self.averagePowerForChannel0)
            self.averagePowerForChannel1 = self.averagePowerForChannel0
        }

        if buffer.format.channelCount > 1 {
            let samples = buffer.floatChannelData![1]
            var avgValue:Float32 = 0
            vDSP_meamgv(samples, 1, &avgValue, inNumberFrames)
            var v:Float = -100
            if avgValue != 0 {
                v = 20.0 * log10f(avgValue)
            }
            self.averagePowerForChannel1 = (self.LEVEL_LOWPASS_TRIG*v) + ((1-self.LEVEL_LOWPASS_TRIG)*self.averagePowerForChannel1)
        }
    }

}


