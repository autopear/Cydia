$(function () {
    var downloading = sizes[0];
    if (downloading == "0.0 B")
        $(".downloading").remove();
    else
        $("#downloading").html($.xml(downloading));

    var resuming = sizes[1];
    if (resuming == "0.0 B")
        $(".resuming").remove();
    else
        $("#resuming").html($.xml(resuming));

    var size = sizes[2];
    var negative;

    if (size.charAt(0) != '-')
        negative = false;
    else {
        negative = true;
        size = size.substr(1);
    }

    $("#disk-key").html(negative ? "Disk Freeing" : "Disk Using");
    $("#disk-value").html($.xml(size));

    var keys = [
        "Install",
        "Reinstall",
        "Upgrade",
        "Downgrade",
        "Remove"
    ];

    for (var i = 0; i != 5; ++i) {
        var list = changes[i];
        var length = list.length;

        if (length != 0) {
            $("#modifications").append("<div>" +
                "<label>" + keys[i] + "</label>" +
                "<div id=\"i" + i + "\"></div>" +
            "</div>");

            var value = "";
            for (var j = 0; j != length; ++j) {
                if (j != 0)
                    value += "<br/>";
                value += $.xml(list[j]);
            }

            $("#i" + i).html(value);
        }
    }
});
