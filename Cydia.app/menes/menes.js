var _assert = function (expr) {
    if (!expr) {
        var message = "_assert(" + expr + ")";
        alert(message);
        throw message;
    }
}

// Compatibility {{{
if (typeof Array.prototype.push != "function")
    Array.prototype.push = function (value) {
        this[this.length] = value;
    };
// }}}

var $ = function (arg, doc) {
    if (this.magic_ != $.prototype.magic_)
        return new $(arg);

    var type = $.type(arg);

    if (type == "function")
        $.ready(arg);
    else if (type == "string") {
        if (doc == undefined)
            doc = document;
        if (arg.charAt(0) == '#')
            return new $([doc.getElementById(arg.substring(1))]);
        else if (arg.charAt(0) == '.')
            return new $(doc.getElementsByClassName(arg.substring(1)));
        else
            return $([doc]).descendants(arg);
    } else {
        _assert(doc == undefined);
        this.set($.array(arg));
        return this;
    }
};

$.type = function (value) {
    var type = typeof value;

    if (
        type == "function" &&
        value.toString != null &&
        value.toString().substring(0, 8) == "[object "
    )
        return "object";
    else
        return type;
};

(function () {
    var ready_ = null;

    $.ready = function (_function) {
        if (ready_ == null) {
            ready_ = [];

            document.addEventListener("DOMContentLoaded", function () {
                for (var i = 0; i != ready_.length; ++i)
                    ready_[i]();
            }, false);
        }

        ready_.push(_function);
    };
})();

/* XXX: verify arg3 overflow */
$.each = function (values, _function, arg0, arg1, arg2) {
    for (var i = 0, e = values.length; i != e; ++i)
        _function(values[i], arg0, arg1, arg2);
};

/* XXX: verify arg3 overflow */
$.map = function (values, _function, arg0, arg1, arg2) {
    var mapped = [];
    for (var i = 0, e = values.length; i != e; ++i)
        mapped.push(_function(values[i], arg0, arg1, arg2));
    return mapped;
};

$.array = function (values) {
    if (values.constructor == Array)
        return values;
    var array = [];
    for (var i = 0; i != values.length; ++i)
        array.push(values[i]);
    return array;
};

$.document = function (node) {
    for (;;) {
        var parent = node.parentNode;
        if (parent == null)
            return node;
        node = parent;
    }
};

$.prototype = {
    magic_: 2041085062,

    add: function (nodes) {
        Array.prototype.push.apply(this, nodes);
    },

    set: function (nodes) {
        this.length = 0;
        this.add(nodes);
    },

    css: function (name, value) {
        $.each(this, function (node) {
            node.style[name] = value;
        });
    },

    append: function (html) {
        $.each(this, function (node) {
            var doc = $.document(node);

            // XXX: implement wrapper system
            var div = doc.createElement("div");
            div.innerHTML = html;

            while (div.childNodes.length != 0) {
                var child = div.childNodes[0];
                node.appendChild(child);
            }
        });
    },

    descendants: function (expression) {
        var descendants = $([]);

        $.each(this, function (node) {
            descendants.add(node.getElementsByTagName(expression));
        });

        return descendants;
    },

    remove: function () {
        $.each(this, function (node) {
            node.parentNode.removeChild(node);
        });
    },

    parent: function () {
        return $($.map(this, function (node) {
            return node.parentNode;
        }));
    }
};

$.scroll = function (x, y) {
    window.scrollTo(x, y);
};

// XXX: document.all?
$.all = function (doc) {
    if (doc == undefined)
        doc = document;
    return $(doc.getElementsByTagName("*"));
};

$.inject = function (a, b) {
    if ($.type(a) == "string") {
        $.prototype[a] = function (value) {
            if (value == undefined)
                return $.map(this, function (node) {
                    return b.get(node);
                });
            else
                $.each(this, function (node, value) {
                    b.set(node, value);
                }, value);
        };
    } else for (var name in a)
        $.inject(name, a[name]);
};

$.inject({
    html: {
        get: function (node) {
            return node.innerHTML;
        },
        set: function (node, value) {
            node.innerHTML = value;
        }
    },

    href: {
        get: function (node) {
            return node.href;
        },
        set: function (node, value) {
            node.href = value;
        }
    },

    value: {
        get: function (node) {
            return node.value;
        },
        set: function (node, value) {
            node.value = value;
        }
    }
});

// Event Registration {{{
// XXX: unable to remove registration
$.prototype.event = function (event, _function) {
    $.each(this, function (node) {
        // XXX: smooth over this pointer ugliness
        if (node.addEventListener)
            node.addEventListener(event, _function, false);
        else if (node.attachEvent)
            node.attachEvent("on" + event, _function);
        else
            // XXX: multiple registration SNAFU
            node["on" + event] = _function;
    });
};

$.each([
    "click", "load", "submit"
], function (event) {
    $.prototype[event] = function (_function) {
        if (_function == undefined)
            _assert(false);
        else
            this.event(event, _function);
    };
});
// }}}
// Timed Animation {{{
$.interpolate = function (duration, event) {
    var start = new Date();

    var next = function () {
        setTimeout(update, 0);
    };

    var update = function () {
        var time = new Date() - start;

        if (time >= duration)
            event(1);
        else {
            event(time / duration);
            next();
        }
    };

    next();
};
// }}}
// AJAX Requests {{{
// XXX: abstract and implement other cases
$.xhr = function (url, method, headers, data, events) {
    var xhr = new XMLHttpRequest();
    xhr.open(method, url, true);

    for (var name in headers)
        xhr.setRequestHeader(name.replace(/_/, "-"), headers[name]);

    if (events == null)
        events = {};

    xhr.onreadystatechange = function () {
        if (xhr.readyState == 4)
            if (events.complete != null)
                events.complete(xhr.responseText);
    };

    xhr.send(data);
};

$.call = function (url, post, onsuccess) {
    var events = {};

    if (onsuccess != null)
        events.complete = function (text) {
            onsuccess(eval(text));
        };

    if (post == null)
        $.xhr(url, "POST", null, null, events);
    else
        $.xhr(url, "POST", {
            Content_Type: "application/json"
        }, $.json(post), events);
};
// }}}
// WWW Form URL Encoder {{{
$.form = function (parameters) {
    var data = "";

    var ampersand = false;
    for (var name in parameters) {
        if (!ampersand)
            ampersand = true;
        else
            data += "&";

        var value = parameters[name];

        data += escape(name);
        data += "=";
        data += escape(value);
    }

    return data;
};
// }}}
// JSON Serializer {{{
$.json = function (value) {
    if (value == null)
        return "null";

    var type = $.type(value);

    if (type == "number")
        return value;
    else if (type == "string")
        return "\"" + value
            .replace(/\\/, "\\\\")
            .replace(/\t/, "\\t")
            .replace(/\r/, "\\r")
            .replace(/\n/, "\\n")
            .replace(/"/, "\\\"")
        + "\"";
    else if (value.constructor == Array) {
        var json = "[";
        var comma = false;

        for (var i = 0; i != value.length; ++i) {
            if (!comma)
                comma = true;
            else
                json += ",";

            json += $.json(value[i]);
        }

        return json + "]";
    } else if (
        value.constructor == Object &&
        value.toString() == "[object Object]"
    ) {
        var json = "{";
        var comma = false;

        for (var name in value) {
            if (!comma)
                comma = true;
            else
                json += ",";

            json += name + ":" + $.json(value[name]);
        }
        return json + "}";
    } else {
        return value;
    }
};
// }}}
