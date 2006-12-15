var layout_mode = "thin";
var sc_old_border_style;
var shift_init = "true";

if (! ("$" in window))
    $ = function(id) {
        if (document.getElementById)
           return document.getElementById(id);
        return null;
    };

function editdate() {
    if (document.getElementById) {
        var currentdate = document.getElementById('currentdate');
        var modifydate = document.getElementById('modifydate');
        currentdate.style.display = 'none';
        modifydate.style.display = 'inline';
    }
}

function showEntryTabs() {
    if (document.getElementById) {
        var entryTabs = document.getElementById('entry-tabs');
        entryTabs.style.display = 'block';
    }
}

function changeSubmit(prefix, defaultjournal) {
    if (document.getElementById) {
        var usejournal = document.getElementById('usejournal');
        var formsubmit = document.getElementById('formsubmit');
        if (!defaultjournal) {
            var newvalue = prefix;
        } else if (!usejournal || usejournal.value == '') {
            var newvalue = prefix + ' ' + defaultjournal;
        } else {
            var newvalue = prefix + ' ' + usejournal.value;
        }
        formsubmit.value = newvalue;
    }
}

function pageload (dotime) {
    if (dotime) settime();
    if (!document.getElementById) return false;

    var remotelogin = $('remotelogin');
    if (! remotelogin) return;
    var remotelogin_content = $('remotelogin_content');
    if (! remotelogin_content) return;
    remotelogin_content.onclick = altlogin;
    f = document.updateForm;
    if (! f) return false;

    var userbox = f.user;
    if (! userbox) return false;
    if (userbox.value) altlogin();
 
    return false;
}

function customboxes (e) {
    if (! e) var e = window.event;
    if (! document.getElementById) return false;
    
    f = document.updateForm;
    if (! f) return false;
    
    var custom_boxes = $('custom_boxes');
    if (! custom_boxes) return false;
    
    if (f.security.selectedIndex != 3) {
        custom_boxes.style.display = 'none';
        return false;
    }

    var altlogin_username = $('altlogin_username');    
    if (altlogin_username != undefined && (altlogin_username.style.display == 'table-row' ||
                                           altlogin_username.style.display == 'block')) {
        f.security.selectedIndex = 0;
        custom_boxes.style.display = 'none';
        alert("Custom security is only available when posting as the logged in user.");
    } else {
        custom_boxes.style.display = 'block';
    }
    
    if (e) {
        e.cancelBubble = true;
        if (e.stopPropagation) e.stopPropagation();
    }
    return false;
}

function altlogin (e) {
    var agt   = navigator.userAgent.toLowerCase();
    var is_ie = ((agt.indexOf("msie") != -1) && (agt.indexOf("opera") == -1));

    if (! e) var e = window.event;
    if (! document.getElementById) return false;
    
    var altlogin_wrapper = $('altlogin_wrapper');
    if (! altlogin_wrapper) return false;
    altlogin_wrapper.style.display = 'block';
   
    var remotelogin = $('remotelogin');
    if (! remotelogin) return false;
    remotelogin.style.display = 'none';
    
    var usejournal_list = $('usejournal_list');
    if (! usejournal_list) return false;
    usejournal_list.style.display = 'none';

    var readonly = $('readonly');
    var userbox = f.user;
    if (!userbox.value && readonly) {
        readonly.style.display = 'none';
    }

    var userpic_list = $('userpic_select_wrapper');
    if (userpic_list) {
        userpic_list.style.display = 'none';
    }

    var userpic_preview = $('userpic_preview');
    if (userpic_preview) {
        userpic_preview.style.display = 'none';
    }

    var mood_preview = $('mood_preview');
    mood_preview.style.display = 'none';

    f = document.updateForm;
    if (! f) return false;
    f.action = 'update.bml?altlogin=1';
    
    var custom_boxes = $('custom_boxes');
    if (! custom_boxes) return false;
    custom_boxes.style.display = 'none';
    if (f.security) {
        f.security.options[3] = null;
    }
    
    f.security.selectedIndex = 0;

    if (e) {
        e.cancelBubble = true;
        if (e.stopPropagation) e.stopPropagation();
    }

    changeSubmit('Post to Journal');

    return false;    
}

function insertFormHints() {
    var subject = $('subject');
    var subjectHint = $('formhint-subject').value;          // get value of hidden input
    // alert(subjectHint);
    DOM.addEventListener(subject, "focus", function (evt) { 
        if (subject.value == subjectHint) {
            subject.value = '';
        }
    });
    DOM.addEventListener(subject, "blur",  function (evt) { 
        if (subject.value == '') {
            subject.value = subjectHint;
        }
    });
}

function defaultDate() {
    $('currentdate').style.display = 'block';
    $('modifydate').style.display = 'none';
}

function insertViewThumbs() {
    var lj_userpicselect = $('lj_userpicselect');
    lj_userpicselect.innerHTML = 'View Thumbnails';
}

function mood_preview() {
    if (! document.getElementById) return false;
    var mood_list  = document.getElementById('prop_current_moodid'); // get select
    var moodid = mood_list[mood_list.selectedIndex].value; // get value of select
    if (moodid == "") {
        if ($('mood_preview')) {
            moodPreview = $('mood_preview');
            moodPreview.innerHTML = '';         
        }
        return false
    } else {
        var wrapper = $('prop_mood_wrapper');
        if ($('mood_preview')) {
            moodPreview = $('mood_preview');
            moodPreview.innerHTML = '';
        } else {
            var moodPreview = document.createElement('span');
            moodPreview.id = 'mood_preview';
            wrapper.appendChild(moodPreview);
        } 
        var moodPreviewImage = document.createElement('img');
        moodPreviewImage.id = 'mood_image_preview';
        moodPreviewImage.src = moodpics[moodid];
        var moodPreviewText = document.createElement('span');
        moodPreviewText.id = 'mood_text_preview';
        var mood_custom_text  = $('prop_current_mood').value;
        moodPreviewText.innerHTML = mood_custom_text == "" ? moods[moodid] : mood_custom_text;
        moodPreview.appendChild(moodPreviewImage);
        moodPreview.appendChild(moodPreviewText);
        if (moodPreview.style.display != 'none') {
            $('prop_current_music').className = $('prop_current_music').className + ' narrow';
            $('prop_current_location').className = $('prop_current_location').className + ' narrow';
        }
    }
}

function entryPreview(entryForm) {
    var f=entryForm;
    var action=f.action;
    f.action='/preview/entry.bml'; 
    f.target='preview';
    window.open('','preview','width=760,height=600,resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
    f.submit(); 
    f.action=action; 
    f.target='_self'; 
    return false;
}

function numberOfColumns(items) {
    if (items <= 6) { return 1 }
    else if (items >= 7 && items <= 12) { return 2 }
    else if (items >= 13 && items <= 18) { return 3 }
    else { return 4 }
}
function setColumns(number) {
    // we'll create all our variables here
    // if you want to change the names of any of the ids, change them here
    var listObj = document.getElementById('custom_boxes_list');                  // the actual ul
    var listWrapper = document.getElementById('custom_boxes');      // ul wrapper
    var listContainer = document.getElementById('list-container');  // container for dynamic content

    // create an array of all the LIs in the UL
    if (listObj) {
        var theList = listObj.getElementsByTagName('LI');
    }
    
    if (!listContainer) {   // if div#list-container doesn't exist create it
        var listContainer = document.createElement('div');
        listContainer.setAttribute('id','list-container');
        listWrapper.appendChild(listContainer);
    } else {                // if it does exist, clear out any content
        listContainer.innerHTML = '';
    }

    // create and populate content arrays based on ul#list
    var content = new Array();
    var contentClass = new Array();
    var contentId = new Array();
    for (i=0;i<theList.length;i++) {
        content[i] = theList[i].innerHTML;
        contentClass[i] = theList[i].className;
        contentId[i] = theList[i].id;
    }

    // hide original list
    listObj.style.display = 'none';
    
    // determine number of columns
    if (number) {   // if it's passed as an argument
        var columns = number;
    } else {        // or use the numberOfColumns function to set it
        var columns = numberOfColumns(content.length);
    }

    // divide number of items by columns and round up to get the number of items per column
    var perColumn = Math.ceil(content.length / columns);

    // set the class of list-wrapper to reflect the number of columns
    if ((theList.length / perColumn) <= (columns - 1)) {
        // If the number of items divided by the calculated items per column is less than 
        // the number of columns minus one, the number of columns will be adjusted down by one. 
        // In other words, if you have 9 items and try to break them into 4 columns, the last 
        // column would be empty, so I've made the adjustment automatic.
        columns = columns - 1;
    }
    listWrapper.className = 'columns' + columns;

    for (j=0;j<columns;j++) { // insert columns into list-container
        if ((perColumn * j) >= theList.length) return false;

        var columnCounter = j + 1; // add 1 to give logical ids to ULs
        var ulist = document.createElement('ul');
        // ulist.setAttribute('class','column');
        // ulist.setAttribute('id','column-' + columnCounter);
        listContainer.appendChild(ulist);
        var start = perColumn * j;      // set where the for loop will start
        var end = perColumn * (j+1);    // set where the for loop will end
        for (k=start;k<end;k++) {
            if (content[k]) {
                var listitem = document.createElement('li');
                listitem.setAttribute('class', contentClass[k]);
                listitem.setAttribute('id', contentId[k]);
                listitem.innerHTML = content[k];
                ulist.appendChild(listitem);
            }
        }
    }
    listWrapper.removeChild(listObj);
}

function settime() {
    function twodigit (n) {
        if (n < 10) { return "0" + n; }
        else { return n; }
    }
    
    now = new Date();
    if (! now) return false;
    f = document.updateForm;
    if (! f) return false;
    
    f.date_ymd_yyyy.value = now.getYear() < 1900 ? now.getYear() + 1900 : now.getYear();
    f.date_ymd_mm.selectedIndex = twodigit(now.getMonth());
    f.date_ymd_dd.value = twodigit(now.getDate());
    f.hour.value = twodigit(now.getHours());
    f.min.value = twodigit(now.getMinutes());

    f.date_diff.value = 1;

    var mNames = new Array("January", "February", "March", 
        "April", "May", "June", "July", "August", "September", 
        "October", "November", "December");
    var currentdate = document.getElementById('currentdate-date');
    var cMonth = now.getMonth();
    var cDay = now.getDate();
    var cYear = now.getYear() < 1900 ? now.getYear() + 1900 : now.getYear();
    var cHour = now.getHours();
    var cMinute = twodigit(now.getMinutes());
    currentdate.innerHTML = mNames[cMonth] + " " + cDay + ", " + cYear + ", " + cHour + ":" + cMinute;
    
    return false;
}

///////////////////// Insert Object code

var InOb = new Object;

InOb.fail = function (msg) {
    alert("FAIL: " + msg);
    return false;
};

// image upload stuff
InOb.onUpload = function (surl, furl, swidth, sheight) {
    var ta = $("updateForm");
    if (! ta) return InOb.fail("no updateform");
    ta = ta.event;
    ta.value = ta.value + "\n<a href=\"" + furl + "\"><img src=\"" + surl + "\" width=\"" + swidth + "\" height=\"" + sheight + "\" border='0'/></a>";
};


InOb.onInsURL = function (url) {
        var ta = $("updateForm");
        var fail = function (msg) {
            alert("FAIL: " + msg);
            return 0;
        };
        if (! ta) return fail("no updateform");
        ta = ta.event;
        ta.value = ta.value + "\n<img src=\"" + url + "\" />";
};


var currentPopup;        // set when we make the iframe
var currentPopupWindow;  // set when the iframe registers with us and we setup its handlers
function onInsertObject (include) {
    InOb.onClosePopup();

    //var iframe = document.createElement("iframe");
    var iframe = document.createElement("div");
    iframe.id = "updateinsobject";
    iframe.className = 'updateinsobject';
    iframe.style.overflow = "hidden";
    iframe.style.position = "absolute";
    iframe.style.border = "0";
    iframe.style.backgroundColor = "#fff";
    iframe.style.overflow = "hidden";

    //iframe.src = include;
    iframe.innerHTML = "<iframe id='popupsIframe' style='border:none' frameborder='0' width='100%' height='100%' src='" + include + "'></iframe>";
    
    currentPopup = iframe;
    document.body.appendChild(iframe);

    setTimeout(function () { document.getElementById('popupsIframe').setAttribute('src', include); }, 500);
    InOb.smallCenter();
}
// the select's onchange:
InOb.handleInsertSelect = function () {
    var objsel = $('insobjsel');
    if (! objsel) { return InOb.fail('can\'t get insert select'); }

    var selected = objsel.selectedIndex;
    var include;

    objsel.selectedIndex = 0;

    if (selected == 0) {
        return true;
    } else if (selected == 1) {
        include = 'imgupload.bml';
    } else {
        alert('Unknown index selected');
        return false;
    }

    onInsertObject(include);

    return true;
};

InOb.handleInsertImage = function () {
    var include;
    include = '/imgupload.bml';
    onInsertObject(include);
    return true;
}
InOb.handleInsertVideo = function() {
    var videoUrl = prompt('Please enter a video URL:');
    var draft = $('draft');
    var video = "<lj-template name=\"video\">" + videoUrl + "</lj-template>";
    draft.value = draft.value + video;
}

InOb.onClosePopup = function () {
    if (! currentPopup) return;
    document.body.removeChild(currentPopup);
    currentPopup = null;
};

InOb.setupIframeHandlers = function () {
    var ife = $("popupsIframe");  //currentPopup;
    if (! ife) { return InOb.fail('handler without a popup?'); }
    var ifw = ife.contentWindow;
    currentPopupWindow = ifw;
    if (! ifw) return InOb.fail("no content window?");

    var el;

    el = ifw.document.getElementById("fromurl");
    if (el) el.onfocus = function () { return InOb.selectRadio("fromurl"); };
    el = ifw.document.getElementById("fromurlentry");
    if (el) el.onfocus = function () { return InOb.selectRadio("fromurl"); };
    if (el) el.onkeypress = function () { return InOb.clearError(); };
    el = ifw.document.getElementById("fromfile");
    if (el) el.onfocus = function () { return InOb.selectRadio("fromfile"); };
    el = ifw.document.getElementById("fromfileentry");
    if (el) el.onclick = el.onfocus = function () { return InOb.selectRadio("fromfile"); };
    el = ifw.document.getElementById("fromfb");
    if (el) el.onfocus = function () { return InOb.selectRadio("fromfb"); };
    el = ifw.document.getElementById("btnPrev");
    if (el) el.onclick = InOb.onButtonPrevious;

};

InOb.selectRadio = function (which) {
    if (! currentPopup) { alert('no popup');
                          alert(window.parent.currentPopup);
 return false; }
    if (! currentPopupWindow) return InOb.fail('no popup window');

    var radio = currentPopupWindow.document.getElementById(which);
    if (! radio) return InOb.fail('no radio button');
    radio.checked = true;

    var fromurl  = currentPopupWindow.document.getElementById('fromurlentry');
    var fromfile = currentPopupWindow.document.getElementById('fromfileentry');
    var submit   = currentPopupWindow.document.getElementById('btnNext');
    if (! submit) return InOb.fail('no submit button');

    // clear stuff
    if (which != 'fromurl') {
        fromurl.value = '';
    }

    if (which != 'fromfile') {
        var filediv = currentPopupWindow.document.getElementById('filediv');
        filediv.innerHTML = filediv.innerHTML;
    }

    // focus and change next button
    if (which == "fromurl") {
        submit.value = 'Insert';
        fromurl.focus();
    }

    else if (which == "fromfile") {
        submit.value = 'Upload';
        fromfile.focus();
    }

    else if (which == "fromfb") {
        submit.value = "Next -->";  // &#x2192 is a right arrow
        // fromfile.focus();
    }

    return true;
};

// getElementById
InOb.popid = function (id) {
    var popdoc = currentPopupWindow.document;
    return popdoc.getElementById(id);
};

InOb.onSubmit = function () {
    var fileradio = InOb.popid('fromfile');
    var urlradio  = InOb.popid('fromurl');
    var fbradio   = InOb.popid('fromfb');

    var form = InOb.popid('insobjform');
    if (! form) return InOb.fail('no form');

    var div_err = InOb.popid('img_error');
    if (div_err) { div_err.style.display = 'block'; }
    if (! div_err) return InOb.fail('Unable to get error div');

    var setEnc = function (vl) {
        form.encoding = vl;
        if (form.setAttribute) {
            form.setAttribute("enctype", vl);
        }
    };

    if (fileradio && fileradio.checked) {
        form.action = currentPopupWindow.fileaction;
        setEnc("multipart/form-data");
        return true;
    }

    if (urlradio && urlradio.checked) {
        var url = InOb.popid('fromurlentry');
        if (! url) return InOb.fail('Unable to get url field');

        if (url.value == '') {
            InOb.setError('You must specify the image\'s URL');
            return false;
        } else if (url.value.match(/html?$/i)) {
            InOb.setError('It looks like you are trying to insert a web page, not an image');
            return false;
        }

        setEnc("application/x-www-form-urlencoded");
        form.action = currentPopupWindow.urlaction;
        return true;
    }

    if (fbradio && fbradio.checked) {
        InOb.fotobilderStepOne();
        return false;
    }

    alert('unknown radio button checked');
    return false;
};

InOb.showSelectorPage = function () {
    var div_if = InOb.popid("img_iframe_holder");
    var div_fw = InOb.popid("img_fromwhere");
    div_fw.style.display = "block";
    div_if.style.display = "none";
    InOb.setPreviousCb(null);

    InOb.setTitle('Insert Image');

    setTimeout(function () {  InOb.smallCenter(); }, 200);
};

InOb.fotobilderStepOne = function () {
    InOb.fullCenter();

    var div_if = InOb.popid("img_iframe_holder");
    var windims = DOM.getClientDimensions();
    DOM.setHeight(div_if, windims.y - 110);

    var div_fw = InOb.popid("img_fromwhere");
    div_fw.style.display = "none";
    div_if.style.display = "block";
    var url = currentPopupWindow.fbroot + "/getgals";

    var titlebar = InOb.popid('insObjTitle');
    var tdims = DOM.getDimensions(titlebar);

    var navbar = InOb.popid('insobjNav');
    var ndims = DOM.getDimensions(navbar);

    var h = (ndims.offsetTop - tdims.offsetBottom);
    h -= 25;

    div_if.innerHTML = "<iframe id='fbstepframe' src=\"" + url + "\" height=\"" + h + "\" width='99%' frameborder='0'></iframe>";
    div_if.style.width = 'auto';
    div_if.style.border = '0px solid';

    InOb.setPreviousCb(InOb.showSelectorPage);
}

InOb.fullCenter = function () {
    var windims = DOM.getClientDimensions();

    DOM.setHeight(currentPopup, windims.y - 40);
    DOM.setWidth(currentPopup, windims.x - 55);
    DOM.setTop(currentPopup, (40 / 2));
    DOM.setLeft(currentPopup, (40 / 2));

    scroll(0,0);

    window.onresize = function() { return InOb.fullCenter(); };
};

InOb.smallCenter = function () {
    var windims = DOM.getClientDimensions();

    DOM.setHeight(currentPopup, 300);
    DOM.setWidth(currentPopup, 700);
    DOM.setTop(currentPopup, (windims.y - 300) / 2);
    DOM.setLeft(currentPopup, (windims.x - 715) / 2);

    scroll(0,0);

    window.onresize = function() { return InOb.smallCenter(); };
};

InOb.setPreviousCb = function (cb) {
    InOb.cbForBtnPrevious = cb;
    InOb.popid("btnPrev").style.display = cb ? "block" : "none";
};

// all previous clicks come in here, then we route it to the registered previous handler
InOb.onButtonPrevious = function () {
    InOb.showNext();

    if (InOb.cbForBtnPrevious)
         return InOb.cbForBtnPrevious();

    // shouldn't get here, but let's ignore the event (which would do nothing anyway)
    return true;
};

InOb.setError = function (errstr) {
    var div_err = InOb.popid('img_error');
    if (! div_err) return false;

    div_err.innerHTML = errstr;
    return true;
};


InOb.clearError = function () {
    var div_err = InOb.popid('img_error');
    if (! div_err) return false;

    div_err.innerHTML = '';
    return true;
};

InOb.disableNext = function () {
    var next = currentPopupWindow.document.getElementById('btnNext');
    if (! next) return InOb.fail('no next button');

    next.disabled = true;

    return true;
};

InOb.enableNext = function () {
    var next = currentPopupWindow.document.getElementById('btnNext');
    if (! next) return InOb.fail('no next button');

    next.disabled = false;

    return true;
};

InOb.hideNext = function () {
    var next = currentPopupWindow.document.getElementById('btnNext');
    if (! next) return InOb.fail('no next button');

    DOM.addClassName(next, 'display_none');

    return true;
};

InOb.showNext = function () {
    var next = currentPopupWindow.document.getElementById('btnNext');
    if (! next) return InOb.fail('no next button');

    DOM.removeClassName(next, 'display_none');

    return true;
};

InOb.setTitle = function (title) {
    var wintitle = currentPopupWindow.document.getElementById('wintitle');
    wintitle.innerHTML = title;
};


/* ******************** DRAFT SUPPORT ******************** */

  /* RULES:
    -- don't save if they have typed in last 3 seconds, unless it's been
       15 seconds.  otherwise save at most every 10 seconds, if dirty.
  */

var LJDraft = {};

LJDraft.saveInProg = false;
LJDraft.epoch      = 0;
LJDraft.lastSavedBody = "";
LJDraft.prevCheckBody = "";
LJDraft.lastTypeTime  = 0;
LJDraft.lastSaveTime  = 0;
LJDraft.autoSaveInterval = 10;
LJDraft.savedMsg = "Autosaved at [[time]]";

LJDraft.save = function (drafttext, cb) {
    var callback = cb;  // old safari closure bug
    if (LJDraft.saveInProg)
        return;

    LJDraft.saveInProg = true;

    var finished = function () {
        LJDraft.saveInProg = false;
        if (callback) callback();
    };

    HTTPReq.getJSON({
      method: "POST",
      url: "/tools/endpoints/draft.bml",
      onData: finished,
      onError: function () { LJDraft.saveInProg = false; },
      data: HTTPReq.formEncoded({"saveDraft": drafttext})
    });
};

LJDraft.startTimer = function () {
    setInterval(LJDraft.checkIfDirty, 1000);  // check every second
    LJDraft.epoch = 0;
};

LJDraft.checkIfDirty = function () {
    LJDraft.epoch++;
    var curBody;

    if (!$("draft")) return false;
    if ($("draft").style.display == 'none') { // Need to check this to deal with hitting the back button
        // Since they may start using the RTE in the middle of writing their
        // entry, we should just get the editor each time.
        if (! FCKeditorAPI) return;
        var oEditor = FCKeditorAPI.GetInstance('draft');
        if (oEditor.GetXHTML) {
            curBody = oEditor.GetXHTML(true);
        }
    } else {
        curBody = $("draft").value;
    }

    // no changes to save
    if (curBody == LJDraft.lastSavedBody)
    return;

    // at this point, things are dirty.

    // see if they've typed in the last second.  if so,
    // we'll want to note their last type time, and defer
    // saving until they settle down, unless they've been
    // typing up a storm and pass our 15 second barrier.
    if (curBody != LJDraft.prevCheckBody) {
        LJDraft.lastTypeTime  = LJDraft.epoch;
        LJDraft.prevCheckBody = curBody;
    }

    if (LJDraft.lastSaveTime < LJDraft.lastTypeTime - 15) {
        // let's fall through and save!  they've been busy.
    } else if (LJDraft.lastTypeTime > LJDraft.epoch - 3) {
        // they're recently typing, don't save.  let them finish.
        return;
    } else if (LJDraft.lastSaveTime > LJDraft.epoch - LJDraft.autoSaveInterval) {
        // we've saved recently enough.
        return;
    }

    // async save, and pass in our callback
    var curEpoch = LJDraft.epoch;
    LJDraft.save(curBody, function () {
        var msg = LJDraft.savedMsg.replace(/\[\[time\]\]/, LJDraft.getTime());
        $("draftstatus").innerHTML = "<span>" + msg + "</span>";
        LJDraft.lastSaveTime  = curEpoch; /* capture lexical.  remember: async! */
        LJDraft.lastSavedBody = curBody;
    });
};

LJDraft.getTime = function () {
    var date = new Date();
    var hour, minute, sec, time;

    hour = date.getHours();
    if (hour >= 12) {
        time = ' PM';
    } else {
        time = ' AM';
    }

    if (hour > 12) {
        hour -= 12;
    } else if (hour == 0) {
        hour = 12;
    }

    minute = date.getMinutes();
    if (minute < 10) {
        minute = '0' + minute;
    }

    sec = date.getSeconds();
    if (sec < 10) {
        sec = '0' + sec;
    }

    time = hour + ':' + minute + ':' + sec + time;
    return time;
}
