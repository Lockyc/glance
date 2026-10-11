import AppKit

/// Zoom menu items target the first responder: the viewer zooms the image, the grid resizes tiles.
@objc protocol ZoomActions {
    func zoomIn(_ sender: Any?)
    func zoomOut(_ sender: Any?)
    @objc optional func actualSize(_ sender: Any?)
    @objc optional func zoomToFit(_ sender: Any?)
}
