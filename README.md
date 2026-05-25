# Aidoku BGTaskScheduler identifier Fix

when sideloading Aidoku via a developer account. a Team ID is appended to BGTaskScheduler related identifiers, making Aidoku unable to recognize them thus breaking most features that should work on the background. 

To fix this, I added my own Team ID to the target identifiers located at iOS/info.plist
