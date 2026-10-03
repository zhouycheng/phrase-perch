import CoreGraphics
import Foundation

func dockPolicyChangeNeeded(currentDockVisible: Bool, requestedDockVisible: Bool) -> Bool {
    currentDockVisible != requestedDockVisible
}
