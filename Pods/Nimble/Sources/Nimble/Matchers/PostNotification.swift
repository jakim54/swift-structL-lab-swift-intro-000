import Foundation

internal class NotificationCollector {
    private(set) var observedNotifications: [Notification]
    private let notificationCenter: NotificationCenter
    #if _runtime(_ObjC)
    private var token: AnyObject?
    #else
    private var token: NSObjectProtocol?
    #endif

    required init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
        self.observedNotifications = []
    }

    func startObserving() {
        self.token = self.notificationCenter.addObserver(forName: nil, object: nil, queue: nil) {
            // linux-swift gets confused by .append(n)
            [weak self] n in self?.observedNotifications.append(n)
        }
    }

    deinit {
        #if _runtime(_ObjC)
            if let token = self.token {
                self.notificationCenter.removeObserver(token)
            }
        #else
            if let token = self.token as? AnyObject {
                self.notificationCenter.removeObserver(token)
            }
        #endif
    }
}

private let mainThread = pthread_self()

let notificationCenterDefault = NotificationCenter.default

public func postNotifications<T>(
    _ notificationsMatcher: T,
    fromNotificationCenter center: NotificationCenter = notificationCenterDefault)
    -> MatcherFunc<Any>
    where T: Matcher, T.ValueType == [Notification]
{
    let _ = mainThread // Force lazy-loading of this value
    let collector = NotificationCollector(notificationCenter: center)
    collector.startObserving()
    var once: Bool = false
    return MatcherFunc { actualExpression, failureMessage in
        let collectorNotificationsExpression = Expression(memoizedExpression: { _ in
            return collector.observedNotifications
            }, location: actualExpression.location, withoutCaching: true)

        assert(pthread_equal(mainThread, pthread_self()) != 0, "Only expecting closure to be evaluated on main thread.")
        if !once {
            once = true
            _ = try actualExpression.evaluate()
        }

        let match = try notificationsMatcher.matches(collectorNotificationsExpression, failureMessage: failureMessage)
        if collector.observedNotifications.isEmpty {
            failureMessage.actualValue = "no notifications"
        } else {
            failureMessage.actualValue = "<\(stringify(collector.observedNotifications))>"
        }
        return match
    }
}
