var colors = ["#9090e0", "#4d4d70", "#7d7da0", "#7da0e0", "#d0d0f0", "#7070e0"];

var list = function (legend, color, name, value) {
    legend.append('<div class="key">' +
        '<div class="color" style="background-color: ' + color + '"><div></div></div>' +
        '<div class="name">' + name + ' (' + Math.round(value * 1000) / 10 + '%)</div>' +
    '</div>');
};

console.log(cydia.statfs("/"));

var cut = function (parent, color, fraction, z) {
    var deg = Math.round(360 * fraction);
    if (deg < 2)
        deg = 2;
    parent.append('<div class="xslice" style="' +
        'background-color: ' + color + ';' +
        '-webkit-transform: rotate(' + deg + 'deg);' +
        'z-index: ' + z + ';' +
    '"></div>');
};

var chart = function (right, left, slices) {
    var total = 0;
    for (var i = 0; i != slices.length; ++i) {
        var slice = slices[i];
        var z = slices.length - i;
        if (slice[1] > 0.5)
            cut(right, slice[0], total + 0.5, z);
        total += slice[1];
        cut(total > 0.5 ? left : right, slice[0], total, z);
    }
};

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

    var slices = [];

    if (folders != null)
        for (var i = 0; i != folders.length; ++i) {
            var folder = folders[i];
            var usage = cydia.du(folder[1]);
            if (usage == null)
                usage = 0;
            var color = colors[i + 2];
            var percent = usage / kb;
            list(legend, color, folder[0], percent);
            slices.push([color, percent]);
            used += usage;
        }

    var free = statfs[0] * statfs[2] / 1024;
    var other = (kb - free - used) / kb;

    slices.push([colors[0], other]);
    chart($("#" + name + "-right"), $("#" + name + "-left"), slices);

    list(legend, colors[0], folders == null ? "Used" : "Other", other);
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
