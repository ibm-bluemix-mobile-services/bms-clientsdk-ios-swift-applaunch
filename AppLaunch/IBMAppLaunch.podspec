Pod::Spec.new do |s|

  s.name         = 'IBMAppLaunch'
  s.version      = '1.0.1'
  s.summary      = 'Swift Client SDK for IBM Cloud App Launch Service'
  s.description  = 'IBM® App Launch for IBM Cloud Services enables app owners to launch features to mobile apps at speed and measure their impact by controlling the targeted audience. The app owner can work with app developers to define key performance indicators for the features, collect responses and decide on feature roll-outs or roll-backs. The service also provides ability to test multiple variants of application features, user interface and messages and empower you to make decisions based on the feedback.'
  s.homepage     = 'https://github.com/ibm-bluemix-mobile-services/bms-clientsdk-swift-applaunch'
  s.license      = 'Apache License, Version 2.0'
  s.authors      = { 'IBM Bluemix Services Mobile SDK' => 'mobilsdk@us.ibm.com' }
  s.source       = { :git => 'https://github.com/ibm-bluemix-mobile-services/bms-clientsdk-swift-applaunch.git', :tag => s.version }
  s.source_files = 'AppLaunch/Source/**/*.swift'


  s.dependency 'BMSCore', '~> 2.0'
  s.dependency 'SwiftyJSON'
  s.ios.deployment_target = '9.0'

end