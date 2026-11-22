// 绑哪儿 iOS 壳注入脚本（勿改网页源码，壳层在这里补齐 WKWebView 的短板）
//
// 背景：网页版「导出备份」是创建一个 blob: 的 <a download> 再 click()，
// 浏览器里会下载文件，但 WKWebView 对 blob 下载默认静默失败。
// 这里在 document start 拦截这类点击：把 blob 读成 base64 发给原生层，
// 原生层写临时文件后弹系统分享面板（UIActivityViewController）让用户存到「文件」。
(function () {
    if (window.__bindExportBridgeInstalled) return;
    window.__bindExportBridgeInstalled = true;

    document.addEventListener('click', function (e) {
        var node = e.target;
        var a = node && node.closest ? node.closest('a[download]') : null;
        if (!a) return;
        var href = a.getAttribute('href') || '';
        if (href.indexOf('blob:') !== 0) return;

        e.preventDefault();
        e.stopPropagation();

        var name = a.getAttribute('download') || 'bind-backup.json';
        fetch(href)
            .then(function (r) { return r.blob(); })
            .then(function (blob) {
                var reader = new FileReader();
                reader.onload = function () {
                    var result = String(reader.result || '');
                    var base64 = result.split(',')[1] || '';
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.exportFile) {
                        window.webkit.messageHandlers.exportFile.postMessage({ name: name, base64: base64 });
                    }
                };
                reader.readAsDataURL(blob);
            })
            .catch(function () { /* 读不出来就静默，网页侧已有 toast 逻辑不受影响 */ });
    }, true);
})();
