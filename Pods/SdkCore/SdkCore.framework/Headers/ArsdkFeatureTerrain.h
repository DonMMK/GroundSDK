/** Generated, do not edit ! */

#import <Foundation/Foundation.h>

extern short const kArsdkFeatureTerrainUid;

struct arsdk_cmd;

/** Terrain data type */
typedef NS_ENUM(NSInteger, ArsdkFeatureTerrainType) {
    /**
     Unknown value from SdkCore.
     Only used if the received value cannot be matched with a declared value.
     This might occur when the drone or rc has a different sdk base from the controller.
     */
    ArsdkFeatureTerrainTypeSdkCoreUnknown = -1,

    /** No data. */
    ArsdkFeatureTerrainTypeNone = 0,

    /** DTED data. */
    ArsdkFeatureTerrainTypeDted = 1,

};
#define ArsdkFeatureTerrainTypeCnt 2

/** Line of sight calibration state */
typedef NS_ENUM(NSInteger, ArsdkFeatureTerrainCalibrationState) {
    /**
     Unknown value from SdkCore.
     Only used if the received value cannot be matched with a declared value.
     This might occur when the drone or rc has a different sdk base from the controller.
     */
    ArsdkFeatureTerrainCalibrationStateSdkCoreUnknown = -1,

    /** Calibration is required to improve image center coordinates */
    ArsdkFeatureTerrainCalibrationStateRequired = 0,

    /** Drone is calibrated */
    ArsdkFeatureTerrainCalibrationStateOk = 1,

};
#define ArsdkFeatureTerrainCalibrationStateCnt 2

/** Possible issues for calibration */
typedef NS_ENUM(NSInteger, ArsdkFeatureTerrainCalibrationIssue) {
    /**
     Unknown value from SdkCore.
     Only used if the received value cannot be matched with a declared value.
     This might occur when the drone or rc has a different sdk base from the controller.
     */
    ArsdkFeatureTerrainCalibrationIssueSdkCoreUnknown = -1,

    /** Drone is too close to perform accurate calibration */
    ArsdkFeatureTerrainCalibrationIssueTooClose = 0,

    /** Drone is too low to perform accurate calibration */
    ArsdkFeatureTerrainCalibrationIssueTooLow = 1,

};
#define ArsdkFeatureTerrainCalibrationIssueCnt 2

@interface ArsdkFeatureTerrainCalibrationIssueBitField : NSObject

+ (BOOL)isSet:(ArsdkFeatureTerrainCalibrationIssue)val inBitField:(NSUInteger)bitfield;

+ (void)forAllSetIn:(NSUInteger)bitfield execute:(void (NS_NOESCAPE ^)(ArsdkFeatureTerrainCalibrationIssue val))cb;

@end

@protocol ArsdkFeatureTerrainCallback<NSObject>

@optional

/**
 Altitude of the drone above terrain using terrain maps. 

 - parameter altitude: Altitude(m) of the drone above the terrain, not relevant if type is none
 - parameter type: Terrain type used.
 - parameter grid_precision: grid precision(°), not relevant if type is none
*/
- (void)onAltitudeAboveTerrain:(NSInteger)altitude type:(ArsdkFeatureTerrainType)type gridPrecision:(float)gridPrecision
NS_SWIFT_NAME(onAltitudeAboveTerrain(altitude:type:gridPrecision:));

/**
  

 - parameter state: State of the calibration
 - parameter issue: Reported issue for drone calibration.
Updated whenever it changes.
If calibration_state is not changing to ok,
it indicates the reason of the failure.
*/
- (void)onCalibrationState:(ArsdkFeatureTerrainCalibrationState)state issueBitField:(NSUInteger)issueBitField
NS_SWIFT_NAME(onCalibrationState(state:issueBitField:));


@end

@interface ArsdkFeatureTerrain : NSObject

+ (NSInteger)decode:(struct arsdk_cmd *)command callback:(id<ArsdkFeatureTerrainCallback>)callback;

/**
 For calibration, the drone will assume that the pilot is at the center of the image seen. Gimbal angles will be corrected accordingly 

 - returns: a block that encodes the command
*/
+ (int (^)(struct arsdk_cmd *))calibrateEncoder
NS_SWIFT_NAME(calibrateEncoder());

/**
  

 - returns: a block that encodes the command
*/
+ (int (^)(struct arsdk_cmd *))calibrationResetEncoder
NS_SWIFT_NAME(calibrationResetEncoder());

@end

