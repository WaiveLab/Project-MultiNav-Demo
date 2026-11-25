import UIKit
import TactileMapCore
import TactileMapView

/// Shared by the study and standalone demo.
enum MapAppearance {
    static func configuration(isZoomed: Bool) -> TactileMapViewConfiguration {
        var config = TactileMapViewConfiguration.default
        // NFB-inspired appearance; element identities and feedback stay unchanged.
        let roadBlue = UIColor(red: 2 / 255.0, green: 62 / 255.0, blue: 138 / 255.0, alpha: 1)
        let routeCyan = UIColor(red: 72 / 255.0, green: 202 / 255.0, blue: 228 / 255.0, alpha: 1)
        let intersectionRed = UIColor(red: 193 / 255.0, green: 18 / 255.0, blue: 31 / 255.0, alpha: 1)
        let sidewalkGray = UIColor(white: 158 / 255.0, alpha: 1)
        let endpointYellow = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
        let landmarkPurple = UIColor(red: 123 / 255.0, green: 44 / 255.0, blue: 191 / 255.0, alpha: 1)
        config.backgroundColor = .white
        // Canvas draws built-in landmarks/crosswalks using these dedicated settings.
        config.landmarkColor = landmarkPurple
        config.landmarkWidthMM = 6.0
        config.crosswalkColor = .white
        config.crosswalkWidthMM = 2.8
        config.crosswalkStripeWidthMM = 1.0
        config.crosswalkStripeGapMM = 1.0
        // Reserve room for fixed-size end markers/road caps at the cropped edge.
        config.canvasPadding = PhysicalDimensions.mmToPoints(isZoomed ? 6 : 4) + 4

        config.typeStyles[.start] = ElementStyle(
            color: endpointYellow,
            sizeMM: 6.0,
        )
        config.typeStyles[.onRoute] = ElementStyle(
            color: routeCyan,
            sizeMM: 3.5,
        )
        config.typeStyles[.offRoute] = ElementStyle(
            color: roadBlue,
            sizeMM: 4.0,
            pointShape: .roundedRect(cornerRadius: 3),
        )
        config.typeStyles[.onRouteIntersection] = ElementStyle(
            color: intersectionRed,
            sizeMM: 6.0,
            pointShape: .roundedRect(cornerRadius: 0),
        )
        config.typeStyles[.offRouteIntersection] = ElementStyle(
            color: intersectionRed,
            sizeMM: 6.0,
            pointShape: .roundedRect(cornerRadius: 0),
        )
        config.typeStyles[.end] = ElementStyle(
            color: endpointYellow,
            sizeMM: 6.0,
        )
        config.typeStyles[.landmark] = ElementStyle(
            color: landmarkPurple,
            sizeMM: 6.0,
        )

        //Intersection specific elements
        config.typeStyles[.street] = ElementStyle(
            color: roadBlue,
            sizeMM: 12.0,
        )
        config.typeStyles[.offRouteSidewalk] = ElementStyle(
            color: sidewalkGray,
            sizeMM: 4.0,
        )
        config.typeStyles[.onRouteSidewalk] = ElementStyle(
            color: routeCyan,
            sizeMM: 3.5,
        )
        config.typeStyles[.offRouteCrosswalk] = ElementStyle(
            // The original remains touchable; a non-interactive layer draws stripes.
            color: .clear,
            sizeMM: 2.8,
        )
        config.typeStyles[.onRouteCrosswalk] = ElementStyle(
            color: routeCyan,
            sizeMM: 3.5,
        )
        config.typeStyles[.crosswalk] = ElementStyle(
            color: .white,
            sizeMM: 2.8,
        )
        config.typeStyles[.turn] = ElementStyle(
            color: UIColor(red: 1, green: 0.55, blue: 0, alpha: 1),
            sizeMM: 6.0,
        )
        config.typeStyles[.intersectionCenter] = ElementStyle(
            color: roadBlue,
            sizeMM: 12.0,
            pointShape: .roundedRect(cornerRadius: 0),
        )

        return config
    }
}
