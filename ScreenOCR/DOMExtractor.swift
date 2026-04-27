import Cocoa

final class DOMExtractor {

    struct Element {
        let rect: CGRect    // CG coords (screen, top-left origin)
        let label: String   // tag.class.class — DevTools-style selector
    }

    // MARK: - Public

    static func getDOMElements(from app: NSRunningApplication?, completion: @escaping ([Element]) -> Void) {
        guard let browser = detectBrowser(app) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let js = """
        (function(){
        var z=window.outerWidth/window.innerWidth;
        var ch=window.outerHeight-window.innerHeight*z;
        var sx=window.screenX,sy=window.screenY;
        var R=[],MAX=2000;
        function sel(el){
        var t=(el.tagName||'').toLowerCase();if(!t)return '';
        var s=t;
        var id=el.id;
        if(id&&typeof id==='string'){var fid=id.trim().split(/\\s+/)[0];if(fid)s+='#'+fid;}
        var cn=el.className;
        if(cn&&cn.baseVal!==undefined)cn=cn.baseVal;
        if(typeof cn==='string'){
        var cls=cn.trim().split(/\\s+/).filter(Boolean).slice(0,8);
        if(cls.length)s+='.'+cls.join('.');}
        return s;}
        var all=document.body?document.body.getElementsByTagName('*'):[];
        for(var i=0;i<all.length&&R.length<MAX;i++){
        var el=all[i];
        var t=el.tagName;if(!t)continue;
        var tu=t.toUpperCase();
        if(tu==='SCRIPT'||tu==='STYLE'||tu==='META'||tu==='LINK'||tu==='HEAD')continue;
        var r=el.getBoundingClientRect();
        if(r.width<6||r.height<6)continue;
        if(r.bottom<0||r.top>window.innerHeight||r.right<0||r.left>window.innerWidth)continue;
        var cs=getComputedStyle(el);
        if(cs.display==='none'||cs.visibility==='hidden'||parseFloat(cs.opacity)===0)continue;
        var s=sel(el);if(!s)continue;
        R.push([sx+r.left*z,sy+ch+r.top*z,r.width*z,r.height*z,s]);}
        return JSON.stringify(R);})()
        """

        let source = appleScript(browser: browser, js: js)

        DispatchQueue.global(qos: .userInitiated).async {
            let elements = runElements(source)
            DispatchQueue.main.async { completion(elements) }
        }
    }

    // MARK: - Browser bridge (mirrors SVGExtractor — kept independent to avoid coupling)

    private enum Browser {
        case safari
        case chromium(name: String)
    }

    private static func detectBrowser(_ app: NSRunningApplication?) -> Browser? {
        guard let bid = app?.bundleIdentifier else { return nil }
        let lower = bid.lowercased()
        if lower == "com.apple.safari" {
            ensureSafariJSEnabled()
            return .safari
        }
        let chromiumIDs = [
            "com.google.chrome",
            "company.thebrowser.browser",
            "com.brave.browser",
            "com.microsoft.edgemac",
            "com.vivaldi.vivaldi",
            "com.operasoftware.opera",
            "ai.perplexity.comet",
        ]
        for cid in chromiumIDs where lower == cid {
            ensureJSEnabled(bundleID: bid)
            return .chromium(name: app?.localizedName ?? "Google Chrome")
        }
        if lower.contains("chrome") || lower.contains("chromium") {
            ensureJSEnabled(bundleID: bid)
            return .chromium(name: app?.localizedName ?? "Google Chrome")
        }
        return nil
    }

    private static func ensureJSEnabled(bundleID: String) {
        let key = "AppleScriptEnabled"
        if UserDefaults(suiteName: bundleID)?.bool(forKey: key) == true { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", bundleID, key, "-bool", "true"]
        try? task.run()
        task.waitUntilExit()
    }

    private static func ensureSafariJSEnabled() {
        let key = "AllowJavaScriptFromAppleEvents"
        if UserDefaults(suiteName: "com.apple.Safari")?.bool(forKey: key) == true { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "com.apple.Safari", key, "-bool", "true"]
        try? task.run()
        task.waitUntilExit()
    }

    private static func appleScript(browser: Browser, js: String) -> String {
        let escaped = js.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
        switch browser {
        case .safari:
            return "tell application \"Safari\" to do JavaScript \"\(escaped)\" in document 1"
        case .chromium(let name):
            return """
            tell application "\(name)"
                tell active tab of front window
                    execute javascript "\(escaped)"
                end tell
            end tell
            """
        }
    }

    private static func runElements(_ source: String) -> [Element] {
        guard let script = NSAppleScript(source: source) else { return [] }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return [] }
        guard let json = result.stringValue,
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return arr.compactMap { item in
            guard item.count == 5,
                  let x = (item[0] as? Double) ?? (item[0] as? Int).map(Double.init),
                  let y = (item[1] as? Double) ?? (item[1] as? Int).map(Double.init),
                  let w = (item[2] as? Double) ?? (item[2] as? Int).map(Double.init),
                  let h = (item[3] as? Double) ?? (item[3] as? Int).map(Double.init),
                  let label = item[4] as? String else { return nil }
            return Element(rect: CGRect(x: x, y: y, width: w, height: h), label: label)
        }
    }
}
