var colors = ["#9090e0", "#4d4d70", "#7d7da0", "#7da0e0", "#d0d0f0", "#7070e0"];

var list = function (legend, color, name, value) {
    legend.append('<div class="key">' +
        '<div class="color" style="background-color: ' + color + '"><div></div></div>' +
        '<div class="name">' + name + ' (' + Math.round(value * 1000) / 10 + '%)</div>' +
    '</div>');
};

console.log(cydia.statfs("/"));

var setup = function (name, root, folders) {
    var size = $("#" + name + "-size");
    var statfs = cydia.statfs(root);
    var kb = statfs[0] * statfs[1] / 1024;
    var total = kb / 1024;

    var unit;
    if (total < 1000)
        unit = 'M';
    else {
        total = total / 1024;
        unit = 'G'
    }

    size.html(Math.round(total * 10) / 10 + " " + unit);

    var legend = $("#" + name + "-legend");
    var used = 0;

    if (folders != null)
        for (var i = 0; i != folders.length; ++i) {
            var folder = folders[i];
            var usage = cydia.du(folder[1]);
            list(legend, colors[i + 2], folder[0], usage / kb);
            total += usage;
        }

    var free = statfs[0] * statfs[2] / 1024;
    list(legend, colors[0], folders == null ? "Used" : "Other", (kb - free - total) / kb);
    list(legend, colors[1], "Free", statfs[2] / statfs[1]);
};

$(function () {
    setup("system", "/", null);

    setup("private", "/private/var", [
        ["Themes", "/Library/Themes/"],
        ["iTunes", "/var/mobile/Media/iTunes_Control/"],
        ["App Store", "/var/mobile/Applications/"],
        ["Photos", "/var/mobile/Media/DCIM/"]
    ]);
});
