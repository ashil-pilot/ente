import Flutter
import UIKit
import app_links

class SceneDelegate: FlutterSceneDelegate {
  private let foregroundHeartbeat = ForegroundHeartbeat()

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // app_links 6.x does not consume scene connection options. Flutter forwards
    // warm links and legacy share-intent callbacks through its scene delegate.
    for context in connectionOptions.urlContexts {
      handleInitialLink(context.url)
    }
    for activity in connectionOptions.userActivities {
      if let url = activity.webpageURL {
        handleInitialLink(url)
      }
    }
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    foregroundHeartbeat.start()
    signal(SIGPIPE, SIG_IGN)
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    foregroundHeartbeat.start()
    signal(SIGPIPE, SIG_IGN)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    foregroundHeartbeat.stop()
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    foregroundHeartbeat.stop()
    super.sceneDidDisconnect(scene)
  }

  private func handleInitialLink(_ url: URL) {
    if !url.absoluteString.contains("homeWidget") {
      AppLinks.shared.handleLink(url: url)
    }
  }
}
