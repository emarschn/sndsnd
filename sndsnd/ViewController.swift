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

class ViewController: UIViewController {

    @IBOutlet weak var indicatorView: UIActivityIndicatorView!
    @IBOutlet weak var rec: UIButton!
    @IBOutlet weak var mic: UILabel!

    var audioEngine : AVAudioEngine!
    var mixer : AVAudioMixerNode!
    var recording = false

    let routePickerView = AVRoutePickerView(frame: .init(x: 0, y: 0, width: 40, height: 40))

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

        routePickerView.center = self.view.center;
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
        self.indicator(show: false)
        self.mic.text = ""
        view.addSubview(routePickerView)
    }

    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChangeListener(notification:)), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    func startPassThru() {
        self.recording = true

        let options: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP, .allowBluetooth]
        try! AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.default, policy: .default, options: options)
        try! AVAudioSession.sharedInstance().setActive(true)

        /*let format = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatInt16,
         sampleRate: 44100.0,
         channels: 1,
         interleaved: true)*/

        let sampleRate = AVAudioSession.sharedInstance().sampleRate

        let inFormat = self.audioEngine.inputNode.inputFormat(forBus: 0)

        self.audioEngine.connect(self.audioEngine.inputNode, to: self.mixer, format: inFormat)
        self.audioEngine.connect(self.mixer, to: self.audioEngine.mainMixerNode, format: inFormat)

        self.mixer.installTap(onBus: 0, bufferSize: AVAudioFrameCount(sampleRate * 0.4), format: inFormat, block: { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) -> Void in

            //let audioBuffer : AVAudioBuffer = buffer
            //_ = ExtAudioFileWrite(self.outref!, buffer.frameLength, audioBuffer.audioBufferList)
        })

        try! self.audioEngine.start()

        UIApplication.shared.isIdleTimerDisabled = true

        checkRoutes()
    }

    func stopPassThru() {
        self.recording = false
        self.audioEngine.stop()
        self.mixer.removeTap(onBus: 0)
        try! AVAudioSession.sharedInstance().setActive(false)

        UIApplication.shared.isIdleTimerDisabled = false
    }

    func completion() {
        if self.recording {
            DispatchQueue.main.async {
                self.rec(UIButton())
            }
        }
    }

    func indicator(show: Bool) {
        DispatchQueue.main.async {
            if show {
                self.indicatorView.startAnimating()
                self.indicatorView.isHidden = false
            } else {
                self.indicatorView.stopAnimating()
                self.indicatorView.isHidden = true
            }
        }
    }

    @IBAction func rec(_ sender: Any) {
        if self.recording {
            self.indicator(show: false)
            self.stopPassThru()
            self.rec.setTitle("START", for: .normal)
        } else {
            self.indicator(show: true)
            self.startPassThru()
            self.rec.setTitle("STOP", for: .normal)
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
        mic.isHidden = true
        let route = AVAudioSession.sharedInstance().currentRoute
        for port in route.inputs {
            if port.portType == AVAudioSession.Port.lineIn {
                mic.text = "✅"
                mic.isHidden = false
            } else if port.portType == AVAudioSession.Port.headsetMic {
                mic.text = "🎧"
                mic.isHidden = false
            } else if port.portType == AVAudioSession.Port.builtInMic {
                mic.text = "🎙"
                mic.isHidden = false
            }
        }
    }

}


