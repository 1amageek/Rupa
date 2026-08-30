struct ViewportTimelineSchedulePolicy: Equatable {
    var isPaused: Bool

    init(projectionTransition: ViewportProjectionTransition?) {
        isPaused = projectionTransition == nil
    }
}
