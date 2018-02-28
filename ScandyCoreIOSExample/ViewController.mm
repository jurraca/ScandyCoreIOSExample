//
//  ViewController.m
//  ScandyCoreIOSExample
//
//  Created by Evan Laughlin on 2/22/18.
//  Copyright © 2018 Scandy. All rights reserved.
//

#include <scandy/core/IScandyCore.h>

#import "ViewController.h"

#import <ScandyCoreIOS/ScandyCoreFramework.h>
#import <ScandyCoreIOS/ScandyCoreView.h>

#import <AVFoundation/AVFoundation.h>
#import <GLKit/GLKit.h>

#define RENDER_REFRESH_RATE 1.0/30.0

@implementation ViewController

  // NOTE: minimum scan size should be at least 0.2 meters for bare minimum surface scans because
  // the iPhone X's TrueDepth absolute minimum depth perception is about 0.15 meters.

  // the minimum size of scan volume's dimensions in meters
  float minSize = 0.2;

  // the maximum size of scan volume's dimensions in meters
  float maxSize = 5;

// update scan size based on slider
- (IBAction)scanSizeChanged:(id)sender {
  
  float range = maxSize - minSize;
  
  // normalize the scan size based on default slider value range [0, 1]
  float scan_size = (range * self.scanSizeSlider.value) + minSize;
  
  self.scanSizeLabel.text = [NSString stringWithFormat:@"Scan Size: %.02f m", scan_size];
  
  ScandyCoreManager.scandyCorePtr->setScanSize(scan_size);
}


- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:(BOOL)animated];
  
  dispatch_async(dispatch_get_main_queue(), ^{
    [(ScanView*)self.view resizeView];
  });
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  // Get our ScandyCore object
  // TODO get proper license here
  ScandyCoreManager.scandyCorePtr->setLicense("");
  
  self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
  
  if (!self.context) {
    NSLog(@"Failed to create ES context");
  }
  
  ScanView *view = (ScanView *)self.view;
  view.context = self.context;
  view.drawableDepthFormat = GLKViewDrawableDepthFormat16;
  
  [EAGLContext setCurrentContext:self.context];
  
  self.vtkGestureHandler = [[VTKGestureHandler alloc] initWithView:self.view vtkView:view];
  
  [self.stopScanButton setHidden:true];
  
  [self startPreview];
}

// here you can set the initial scan state with things like scan size, resolution, bounding box offset
// from camera, and so on. All these things can be changed programmatically while the preview is running
// as well, but they cannot change during an active scan.
- (void)setupScanConfiguration{

  // make sure this runs in the same queue as initializeScanner, so our configurations won't get reset
  dispatch_async(dispatch_get_main_queue(), ^{
    // The scan size represents the width, height, and depth (in meters) of the scan volume's bounding box, which
    // must all be the same value.
    // set the initial scan size to 0.5m x 0.5m x 0.5m
    float scan_size = 0.5;
    ScandyCoreManager.scandyCorePtr->setScanSize(scan_size);
    
    // update the scan slider to match for the sake of this example
    self.scanSizeLabel.text = [NSString stringWithFormat:@"Scan Size: %.02f m", scan_size];
    self.scanSizeSlider.value = (scan_size - minSize)/(maxSize - minSize);
  });
  
  
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
}


- (void)requestCamera {
  switch ( [ScandyCoreManager.scandyCameraDelegate startCamera:AVCaptureDevicePositionFront ]  )
  {
    case AVCamSetupResultSuccess:
    {
      dispatch_async( dispatch_get_main_queue(), ^{
        ScandyCoreManager.scandyCorePtr->initializeScanner(scandy::core::ScannerType::TRUE_DEPTH);
        
        ScandyCoreManager.scandyCorePtr->startPreview();
        
        NSLog(@"starting render");
        self.m_render_loop = [NSTimer scheduledTimerWithTimeInterval:RENDER_REFRESH_RATE target:(ScanView*)self.view selector:@selector(render) userInfo:nil repeats:YES];
      } );
      break;
    }
    case AVCamSetupResultCameraNotAuthorized:
    {
      break;
    }
    case AVCamSetupResultSessionConfigurationFailed:
    {
      break;
    }
  }
}

- (IBAction)startScanningPressed:(id)sender {
  [self startScanning];
}

- (IBAction)stopScanningPressed:(id)sender {
  [self stopScanning];
}

- (IBAction)saveMeshPressed:(id)sender {
  
  NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
  NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  [dateFormatter setLocale:enUSPOSIXLocale];
  [dateFormatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
  
  NSDate *now = [NSDate date];
  NSString *iso8601String = [dateFormatter stringFromDate:now];
  
  NSString *fileName = [NSString stringWithFormat:@"scandycoreiosexample_%@.ply", iso8601String];
  
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *documentsDirectory = [paths objectAtIndex:0];
  NSString *filePath = [documentsDirectory stringByAppendingPathComponent:fileName];
  NSLog(@"save file to: %@", filePath);

  // save the mesh!
  ScandyCoreManager.scandyCorePtr->saveMesh(std::string([filePath UTF8String]));
}

- (void)startPreview {
  // Make sure we are not already running and that we have a valid capture directory
  if( !ScandyCoreManager.scandyCorePtr->isRunning()){
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      
      [ScandyCoreManager.scandyCameraDelegate setDeviceTypes:@[AVCaptureDeviceTypeBuiltInTrueDepthCamera]];

      [self requestCamera];
      
      // NOTE: it's important to call this after startPreview because we need the scanner to
      // have been initialized so that the configuration changes will persist
      [self setupScanConfiguration];
      
      // Make sure our view is the right size
      dispatch_async(dispatch_get_main_queue(), ^{
      [(ScanView*)self.view resizeView];
      });
    });
  }
}

- (void)startScanning{
  
  [self.scanSizeLabel setHidden:true];
  [self.scanSizeSlider setHidden:true];
  [self.startScanButton setHidden:true];
  
  [self.stopScanButton setHidden:false];
  
  // Make sure we are running from preview first
  if( ScandyCoreManager.scandyCorePtr->isRunning()){
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      
      [ScandyCoreManager.scandyCameraDelegate setDeviceTypes:@[AVCaptureDeviceTypeBuiltInTrueDepthCamera]];
      
      ScandyCoreManager.scandyCorePtr->startScanning();
    });
  }
}

- (void)stopScanning{
  
  [self.stopScanButton setHidden:true];
  
  // Make sure we are running before trying to stop
  if( ScandyCoreManager.scandyCorePtr->isRunning()){
    dispatch_async(dispatch_get_main_queue(), ^{
      ScandyCoreManager.scandyCorePtr->stopScanning();
    });
    
    // Make sure the pipeline has fully stopped before calling generate mesh
    // this is why we dispatch_asyng on main queue separately
    dispatch_async(dispatch_get_main_queue(), ^{
      ScandyCoreManager.scandyCorePtr->generateMesh();

    });
  }
  
  [self.saveMeshButton setHidden:false];
}


@end
