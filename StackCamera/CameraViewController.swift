//
//  CameraViewController.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 07.11.2022
//

import UIKit
import AVFoundation
import Photos
import SwiftUI

final class CameraViewController: UIViewController {
    
    @AppStorage("tileSize")
    private var tileSize = 0
    
    @AppStorage("burstDestination")
    private var burstDestination = BurstDestination.shareSheet.rawValue
    
    @AppStorage("isImageStabilizationEnabled")
    private var isImageStabilizationEnabled = false
    
    private var spinner: UIActivityIndicatorView!
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }
    
    var imageBuffer: [Data] = []
    
    var startTime: CFAbsoluteTime!
    
    private var tiffTagOrientation = 1
    
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupRotation()
        
        lensSelectorButton.isEnabled = false
        photoButton.isEnabled = false
        previewView.session = session
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
        default:
            setupResult = .notAuthorized
        }
        sessionQueue.async {
            self.configureSession()
        }
        
        spinner = UIActivityIndicatorView(style: .large)
        spinner.color = UIColor.yellow
        previewView.addSubview(self.spinner)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "Stack Camera doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "Stack Camera", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                  options: [:],
                                                  completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "Stack Camera", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ImageSaver.shared.requestAuthorizationIfNeeded { success in
            if !success { self.showAllowFullAccessToPhotoLibraryAlert() }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
                  deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                return
            }
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }
    
    // MARK: - Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    
    private var setupResult: SessionSetupResult = .success
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet private weak var previewView: PreviewView!
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        session.sessionPreset = .photo
        
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            setupLenses()
            if let defaultLens = lenses.first {
                defaultVideoDevice = AVCaptureDevice.default(defaultLens, for: .video, position: .back)
            }
            
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add the photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            photoQualityPrioritizationMode = .quality
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
        
        DispatchQueue.main.async { [self] in
            setupControls()
        }
    }
    
    @IBAction private func resumeInterruptedSession(_ resumeButton: UIButton) {
        sessionQueue.async {
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "Stack Camera", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    // MARK: - Device Configuration
    
    @IBOutlet weak var lensSelectorButton: LensSelectorButton!
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    
    private var lenses: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera]
    
    private var selectedLensIndex = 0
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera, .builtInDualWideCamera],
        mediaType: .video, position: .unspecified
    )
    
    @IBAction func changeLens(_ lensSelectorButton: LensSelectorButton) {
        if selectedLensIndex == lenses.count - 1 {
            selectedLensIndex = 0
        } else {
            selectedLensIndex += 1
        }
        
        lensSelectorButton.isEnabled = false
        photoButton.isEnabled = false
        
        sessionQueue.async { [unowned self] in
            if let videoDevice = AVCaptureDevice.default(self.lenses[self.selectedLensIndex], for: .video, position: .back) {
                do {
                    let currentVideoDevice = self.videoDeviceInput.device
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                    
                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.lensSelectorButton.isEnabled = true
                self.photoButton.isEnabled = true
                
                switch self.lenses[self.selectedLensIndex] {
                case .builtInWideAngleCamera:
                    lensSelectorButton.setLens(.wide)
                case .builtInTelephotoCamera:
                    lensSelectorButton.setLens(.telephoto)
                case .builtInUltraWideCamera:
                    lensSelectorButton.setLens(.ultrawide)
                default: break
                }
                self.setupControls()
            }
        }
    }
    
    private func setupLenses() {
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) == nil {
            lenses.removeAll { $0 == .builtInWideAngleCamera }
        }
        if AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) == nil {
            lenses.removeAll { $0 == .builtInTelephotoCamera }
        }
        if AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) == nil {
            lenses.removeAll { $0 == .builtInUltraWideCamera }
        }
    }
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(
        with focusMode: AVCaptureDevice.FocusMode,
        exposureMode: AVCaptureDevice.ExposureMode,
        at devicePoint: CGPoint,
        monitorSubjectAreaChange: Bool
    ) {
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: - Capturing Photos
    
    private let photoOutput = AVCapturePhotoOutput()
    
    /// - Tag: CapturePhoto
    @IBAction private func capturePhoto(_ photoButton: UIButton) {
        guard ImageSaver.shared.isAuthorized else {
            showAllowFullAccessToPhotoLibraryAlert()
            return
        }
        
        processingIndicatorView.isHidden = false
        processingStatusLabel.text = "1/\(imageCount)"
        let dispatchGroup = DispatchGroup()
        startTime = CFAbsoluteTimeGetCurrent()
        
        let device = self.videoDeviceInput.device
        
        for _ in 1...imageCount {
            dispatchGroup.enter()
            let photoSettings: AVCapturePhotoSettings
            if isImageStabilizationEnabled {
                photoSettings = AVCapturePhotoBracketSettings(
                    rawPixelFormatType: photoOutput.availableRawPhotoPixelFormatTypes.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }!,
                    processedFormat: nil,
                    bracketedSettings: [AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(exposureDuration: self.videoDeviceInput.device.exposureDuration, iso: self.videoDeviceInput.device.iso)]
                )
                (photoSettings as! AVCapturePhotoBracketSettings).isLensStabilizationEnabled = self.photoOutput.isLensStabilizationDuringBracketedCaptureSupported
            } else {
                photoSettings = AVCapturePhotoSettings(
                    rawPixelFormatType: photoOutput.availableRawPhotoPixelFormatTypes.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }!
                )
            }
            
            sessionQueue.async { [self] in
                self.customModeSSValue = device.exposureDuration
                self.customModeISOValue = device.iso
                let delegate = RAWCaptureDelegate()
                captureDelegates[photoSettings.uniqueID] = delegate

                delegate.didFinish = { result in
                    switch result {
                    case .failure:
                        fatalError("Error taking photo")
                    case let .success(rawImage):
                        self.imageBuffer.append(rawImage)
                        self.captureDelegates[photoSettings.uniqueID] = nil
                        DispatchQueue.main.async {
                            self.imagesShotCount += 1
                            self.processingStatusLabel.text = "\(self.imagesShotCount + 1)/\(self.imageCount)"
                        }
                        dispatchGroup.leave()
                    }
                }
                photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
                Thread.sleep(forTimeInterval: 0.050)
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            self.processingStatusLabel.text = "Processing…"
            self.view.layoutIfNeeded()
            
            let diff = CFAbsoluteTimeGetCurrent() - self.startTime
            print("Took \(diff) seconds")
            DispatchQueue.main.async { [self] in
                if formatButton.formatButtonState == .burst {
                    saveDNGBurst(imageBuffer: imageBuffer)
                } else {
                    let tileSize: Int
                    if self.tileSize == 0 {
                        // TODO: Fix 32 and 64 tile sizes
                        // tileSize = iso > 700 ? 32 : 16
                        tileSize = 16
                    } else {
                        tileSize = self.tileSize
                    }
                    let outputTexture = try! alignAndMerge(images: imageBuffer, tileSize: tileSize)
                    print("Output texture created")
                    let referenceURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                    try! imageBuffer[0].write(to: referenceURL, options: .atomic)
                    let dngURL = DNGSaver.createDNG(fromMTLTexture: outputTexture, usingReferenceURL: referenceURL, tiffTagOrientation: tiffTagOrientation)!
                    if formatButton.formatButtonState == .dng {
                        ImageSaver.shared.saveDNG(imageURL: dngURL)
                    } else {
                        ImageSaver.shared.saveCompressedImage(imageURL: dngURL)
                    }
                }

                self.imageBuffer.removeAll()
                self.imagesShotCount = 0
                self.processingIndicatorView.isHidden = true
            }
        }
    }
    
    
    private func saveDNGBurst(imageBuffer: [Data]) {
        var urls: [URL] = []
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let dateString = dateFormatter.string(from: Date())
            for (i, image) in imageBuffer.enumerated() {
                let fileName = "\(dateString)-burst-\(String(format: "%02d", i + 1)).dng"
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try image.write(to: fileURL)
                urls.append(fileURL)
            }
        } catch {
            print("Error: \(error)")
        }
        guard !urls.isEmpty else { return }
        
        switch BurstDestination(rawValue: burstDestination) {
        case .shareSheet:
            let ac = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            self.present(ac, animated: true)
        case .photos:
            PHPhotoLibrary.shared().performChanges {
                for url in urls {
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, fileURL: url, options: nil)
                }
            } completionHandler: { success, error in
                if let error {
                    print("Error saving photo: \(error.localizedDescription)")
                    return
                }
            }
        case .files:
            let docPickerViewController = UIDocumentPickerViewController(forExporting: urls)
            self.present(docPickerViewController, animated: true)
        case .none:
            fatalError("No burst destination selected")
        }
    }
    
    private func showAllowFullAccessToPhotoLibraryAlert() {
        let alert = UIAlertController(
            title: "Allow Access to Photos",
            message: "Please allow full access to your photo library. Stack Camera requires it in order to save images in its own folder.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open App Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString),
                  UIApplication.shared.canOpenURL(url) else {
                assertionFailure("Not able to open app privacy settings")
                return
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(alert, animated: true)
    }

    private var captureDelegates: [Int64: NSObject] = [:]

    private var photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization = .balanced
        

    
    // MARK: - Controls
    
    private var settingValuesObservation = [NSKeyValueObservation]()
    
    @IBOutlet private weak var photoButton: UIButton!
    @IBOutlet private weak var shutterSpeedButton: UIButton!
    @IBOutlet private weak var exposureModeButton: UIButton!
    @IBOutlet private weak var isoButton: UIButton!
    @IBOutlet private weak var imageCountSlider: UISlider!
    @IBOutlet private weak var isoSlider: UISlider!
    @IBOutlet private weak var shutterSpeedSlider: UISlider!
    @IBOutlet private weak var imageCountPicView: UIImageView!
    @IBOutlet private weak var imageCountLabel: UILabel!
    @IBOutlet private weak var autoImageCountButton: UIButton!
    @IBOutlet private weak var settingsImageView: UIImageView!
    @IBOutlet private weak var processingIndicatorView: UIView!
    @IBOutlet private weak var processingStatusLabel: UILabel!
    @IBOutlet private weak var formatButton: FormatButton!
    @IBOutlet private weak var galleryImageView: UIImageView!
    
    private var autoImageCountEnabled: Bool = false
    private var rawPlusEnabled: Bool = false
    private var customModeSSValue: CMTime!
    private var customModeISOValue: Float!
    private var imageCount = 10
    private var imagesShotCount = 0
    
    // In iOS 17, auto exposure may use an ISO value outside the [minISO, maxISO] range. The app crashes if you try to assign that value manually.
    // This computed property works around the issue.
    private var deviceISO: Float {
        let device = videoDeviceInput.device
        let isoValue = videoDeviceInput.device.iso
        let minISO = device.activeFormat.minISO
        let maxISO = device.activeFormat.maxISO
        if isoValue < minISO { return minISO }
        if isoValue > maxISO { return maxISO }
        return isoValue
    }
    
    private func setupControls() {
        settingValuesObservation.removeAll()
        
        imageCountLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        
        isoSlider.isHidden = true
        shutterSpeedSlider.isHidden = true
        processingIndicatorView.isHidden = true
        
        isoSlider.minimumValue = videoDeviceInput.device.activeFormat.minISO
        isoSlider.maximumValue = videoDeviceInput.device.activeFormat.maxISO
        
        settingValuesObservation.append(
            videoDeviceInput.device.observe(\.iso, options: .new) { device, change in
                let isoValue = device.iso
                self.isoButton.configuration?.subtitle = "\(Int(isoValue))"
                self.isoSlider.setValue(isoValue, animated: true)
                
                if self.autoImageCountEnabled {
                    switch Int(isoValue) {
                    case Int.min...32:
                        self.imageCount = 2
                    case 33...1250:
                        self.imageCount = max(2, Int((0.028 * isoValue - 0.7).rounded(.up)))
                    case 1251...Int.max:
                        self.imageCount = 40
                    default:
                        self.imageCount = 40
                    }
                    self.imageCountSlider.value = Float(self.imageCount)
                    self.imageCountLabel.text = "\(self.imageCount)"
                }
            }
        )
        
        
        settingValuesObservation.append(
            videoDeviceInput.device.observe(\.exposureDuration, options: .new) { device, change in
                let newDurationSeconds = device.exposureDuration.seconds
                if (newDurationSeconds < 1) {
                    let digits = Double.maximum(0, 2 + floor(log10(newDurationSeconds)))
                    self.shutterSpeedButton.configuration?.subtitle = String(format: "1/%.*f", digits, 1/newDurationSeconds)
                } else {
                    self.shutterSpeedButton.configuration?.subtitle = String(format: "%.2f", newDurationSeconds)
                }
            }
        )
    }
    
    @IBAction private func isoButtonTapped(_ isoButton: UIButton) {
        let device = videoDeviceInput.device
        guard device.exposureMode == .custom else { return }
        isoSlider.isHidden.toggle()
        shutterSpeedSlider.isHidden = true
    }
    
    @IBAction private func shutterSpeedButtonTapped(_ sender: Any) {
        let device = videoDeviceInput.device
        guard device.exposureMode == .custom else { return }
        shutterSpeedSlider.isHidden.toggle()
        isoSlider.isHidden = true
    }
    
    @IBAction private func isoSliderValueChanged(_ slider: UISlider) {
        let device = videoDeviceInput.device
        guard device.exposureMode == .custom else { return }
        try! device.lockForConfiguration()
        device.setExposureModeCustom(duration: device.exposureDuration, iso: slider.value)
        device.unlockForConfiguration()
        isoButton.configuration?.subtitle = "\(Int(slider.value))"
    }
    
    @IBAction private func imageCountSliderValueChanged(_ slider: UISlider) {
        guard !autoImageCountEnabled else { return }
        imageCount = Int(slider.value)
        imageCountLabel.text = "\(imageCount)"
    }
    
    @IBAction private func shutterSpeedSliderValueChanged(_ slider: UISlider) {
        let device = videoDeviceInput.device

        let kExposureDurationPower = 5; // Higher numbers will give the slider more sensitivity at shorter durations
        
        var p = slider.value
        for _ in 1...kExposureDurationPower {
            p *= slider.value
        }
        
        let minDurationSeconds = device.activeFormat.minExposureDuration.seconds
        let maxDurationSeconds = device.activeFormat.maxExposureDuration.seconds
        let newDurationSeconds = Double(p) * (maxDurationSeconds - minDurationSeconds) + minDurationSeconds;
        
        try! device.lockForConfiguration()
        device.setExposureModeCustom(duration: CMTimeMakeWithSeconds(newDurationSeconds, preferredTimescale: 1000*1000*1000), iso: deviceISO)
        device.unlockForConfiguration()
        
        if (newDurationSeconds < 1) {
            let digits = Double.maximum(0, 2 + Double(floor(log10(newDurationSeconds))))
            self.shutterSpeedButton.configuration?.subtitle = String(format: "1/%.*f", digits, 1/newDurationSeconds)
        } else {
            self.shutterSpeedButton.configuration?.subtitle = String(format: "%.2f", newDurationSeconds)
        }
    }
    
    @IBAction private func exposureModeButtonTapped(_ exposureModeButton: UIButton) {
        let device = videoDeviceInput.device
        try! device.lockForConfiguration()
        if let mode = exposureModeButton.configuration?.subtitle, mode == "Auto" {
            device.setExposureModeCustom(duration: device.exposureDuration, iso: deviceISO)
            exposureModeButton.configuration?.subtitle = "Manual"
            settingValuesObservation.removeAll()
        } else {
            device.exposureMode = .continuousAutoExposure
            exposureModeButton.configuration?.subtitle = "Auto"
            setupControls()
        }
        device.unlockForConfiguration()
    }
    
    @IBAction private func rawPlusButtonTapped(_ button: UIButton) {
        formatButton.changeToNextState()
    }
    
    @IBAction private func galleryButtonTapped(_ sender: Any) {
        UIApplication.shared.open(URL(string: "photos-redirect://")!, options: [:], completionHandler: nil)
    }
    
    @IBAction private func settingsButtonTapped(_ sender: Any) {
        let settingsViewController = UIHostingController(rootView: SettingsView())
        present(settingsViewController, animated: true)
    }
    
    @IBAction private func autoImageCountButtonTapped(_ sender: Any) {
        autoImageCountEnabled.toggle()
        autoImageCountButton.tintColor = autoImageCountEnabled ? .systemYellow : .white
        imageCountSlider.isEnabled = !autoImageCountEnabled
    }
    
    
    // MARK: - KVO and Notifications
    
    private var keyValueObservations = [NSKeyValueObservation]()
    
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has more than one camera.
                self.lensSelectorButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.photoButton.isEnabled = isSessionRunning
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
            guard let systemPressureState = change.newValue else { return }
            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
        }
        keyValueObservations.append(systemPressureStateObservation)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaDidChange),
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: videoDeviceInput.device
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }
    
    private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        /*
         The frame rates used here are only for demonstration purposes.
         Your frame rate throttling may be different depending on your app's camera configuration.
         */
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            do {
                try self.videoDeviceInput.device.lockForConfiguration()
                print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
                self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                self.videoDeviceInput.device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        } else if pressureLevel == .shutdown {
            print("Session stopped running due to shutdown system pressure level.")
        }
    }
    
    // MARK: - Rotation Manager
    
    var rotatableViews: [UIView] = []
    
    private func setupRotation() {
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
        rotatableViews.append(contentsOf: [autoImageCountButton, lensSelectorButton, isoButton, shutterSpeedButton, exposureModeButton, imageCountPicView, imageCountLabel, processingIndicatorView, formatButton, galleryImageView, settingsImageView])
    }
    
    @objc func orientationChanged(_ n: Notification) {
        let orientation = UIDevice.current.orientation
        var transform: CGAffineTransform? = nil
        switch orientation {
        case .landscapeLeft:
            transform = CGAffineTransform(rotationAngle: CGFloat.pi / 2.0)
            tiffTagOrientation = 1 // TOPLEFT
        case .landscapeRight:
            transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2.0)
            tiffTagOrientation = 3 // BOTRIGHT
        case .portrait:
            transform = .identity
            tiffTagOrientation = 6 // RIGHTTOP
        case .portraitUpsideDown:
            transform = CGAffineTransform(rotationAngle: CGFloat.pi)
            tiffTagOrientation = 8 // LEFTBOT
        case .faceDown, .faceUp, .unknown:
            // Preserve the previous state
            break
        @unknown default:
            break
        }
        if let transform {
            rotatableViews.forEach { view in
                UIView.animate(withDuration: 0.25) {
                    view.transform = transform
                }
            }
        }
    }
}
