# encode: UTF-8
editor=123
editor_width=500

margin=260
marginr=400
menu=20
session=null

now=0
changes=0
last_change=0
files={}
open_folders=["arisi/test/uusikansio"]
current=null
pro=null

userid="arisi"

note  = (txt) ->
  $("#rightcolumn").append "<font color='white'>NOTE: #{txt}</font><br>"


sse_data = (src,data) ->
  #console.log "sse:",data
  obj=$("#rightcolumn")
  if data.logs
    arr=obj.html().split("\n")
    if arr.length>100
      obj.html("")
    for l in data.logs
      if src=="$"
        obj.append("<font color='#80ff80'>#{l}</font>")
      else
        obj.append("#{src} #{l}<br>")
    obj.scrollTop($("#rightcolumn")[0].scrollHeight);
  if data.session and src!="$"
    session=data.session
    obj.append "GOT SESSION:#{session}<br>"

have=false
sorter = (a,b) ->
  #if a[a.length-1]=='*'
  #  a = a.slice(0,-1);
  #if b[b.length-1]=='*'
  #  b = b.slice(0,-1);
  x = a.title.toLowerCase()
  y = b.title.toLowerCase()
  console.log "comp ",x,y
  (if x is y then 0 else (if x < y then 1 else -1))

ajax_data = (data) ->
  #console.log "ajax:",data
  if have
    $("#leftcolumn").fancytree("destroy")
  have=true
  if data.note
    note data.note
  if data.alert
    alert data.alert
  if data.flatdir
    $("#leftcolumn").fancytree
      checkbox: false
      icons: false
      keyboard: false
      click: (e,data) ->
        if data.node.folder
          init_editor(data.node.data.fullpath)
        return

      source: data.flatdir
  else if data.dir
    console.log data.dir
    $("#leftcolumn").fancytree
      checkbox: false
      icons: true
      keyboard: false
      extensions: ["dnd","edit","glyph"],
      dnd:
        autoExpandMS: 400
        focusOnClick: true
        preventVoidMoves: true # Prevent dropping nodes 'before self', etc.
        preventRecursiveMoves: true # Prevent dropping nodes on own descendants
        dragStart: (node, data) ->
          console.log "dragstart?? ",node,data
          return true
        dragEnter: (node, data) ->
          console.log "dragenter?? ",node,data
          return true
        dragDrop: (node, data) ->
          console.log "dragdrop?? ",node,"data:",data
          console.log "-->MOVE ",data.otherNode.title
          console.log "-->MOVE ",data.node.title
          console.log "-->MOVE mdoe ",data.hitMode
          data.otherNode.moveTo node, data.hitMode
      edit:
        triggerStart: ["shift+click","mac+enter"]
        beforeEdit: (event, data) ->
          console.log "before Edit?? ",data.node.data.fullpath
          if files[data.node.data.fullpath] and files[data.node.data.fullpath].open
            alert "Cannot Change Name if editing.."
            return false
          return true
        edit: (event, data) ->
          console.log "Edit?? ",data
          return false
        beforeClose: (event, data) ->
          console.log "before colose Edit?? ",data
          return true
        save: (event, data) ->
          console.log "--> ",data.node
          console.log "SAVE?? ",data.node.data.fullpath
          console.log "-->REN ",data.orgTitle
          console.log ".....",data.input.val()
          node = data.node
          $.ajax(
            url: "/demo.json"
            data:
              act: "rename"
              session: session
              fn: data.node.data.fullpath
              folder: data.node.folder
              newname: data.input.val()
          ).done((result) ->
            if result.fn
              node.setTitle result.fn
              node.data.fullpath=result.fullpath
              node.tooltip=result.fullpath
              if node.folder
                console.log "HEY FOLDER RENAMED... LETS RELOAD ALL..."
                files={}
                init_editor pro
            else
              alert "failed to rename: #{result.err}"
              console.log result
              node.setTitle data.orgTitle
            node.render(true)
            return
          ).fail((result) ->
            node.setTitle data.orgTitle
            return
          ).always ->
            #data.input.removeClass "pending"
            return

          return true

      click: (e,data) ->

        if data.node.folder
          console.log "folder!",data.node
          if data.node.title=="newfolder" #nothing for unnamed folder!
            return
          #console.table data.node.children
          if data.node.children
            for c in data.node.children
              #console.log "chid",c.title
              if e.ctrlKey
                if c.title=="newfolder"
                  return
              else
                if c.title=="newfile"
                  return
          if e.ctrlKey
            data.node.addChildren({title: "newfolder",folder:true,fullpath:"#{data.node.data.fullpath}/newfolder",tooltip: "#{data.node.data.fullpath}/newfolder"})
          else
            data.node.addChildren({title: "newfile",fullpath:"#{data.node.data.fullpath}/newfile",tooltip: "#{data.node.data.fullpath}/newfile"})
          #data.node.setSelected(false)
          #data.node.setActive(false)
          #tree_fix()
          return true
        else
          if e.shiftKey
            #console.log "shift -- ignore"
            return true
          #console.log "click:",e,data
          if data.node.title!="newfile"
            loader(data.node.data.fullpath,true)
          #data.node.editStart()
          return true

      source: data.dir
    #open_folders=["arisi/test/uusikansio"]
    #tree_fix true

    git "status"
  root=$("#leftcolumn").fancytree("getRootNode")
  root.sortChildren( null, true);
  #sortChildren: (cmp,deep) ->

@ajax = (data) ->
  #console.log "AJAX: ",args
  data.session=session
  $.ajax
    url: "/demo.json"
    type: "PUSH"
    data: data
    dataType: "json",
    contentType: "application/json; charset=utf-8",
    success: (data) ->
      ajax_data(data)
      if false
        setTimeout (->
          ajax()
          return
        ), 3000
      return
    error: (xhr, ajaxOptions, thrownError) ->
      alert thrownError
      return

ensure_file = (fn) ->
  if not files[fn]
    files[fn]={data:null,valid:false,odata:null, open: false, type: "asciidoc", scroll_row:0, pos: {row:0, column:0},diffs:[], errs:[]}

@saver = (fn,data) ->
  console.log "SAVER: #{fn}, #{data.length}"
  $.ajax
    url: "/demo.json"
    type: "POST"
    data:
      act: "save"
      data: data
      fn: fn
      type: files[fn].type
      session: session
      path: pro
    dataType: "json",
    contentType: "application/json; charset=utf-8",
    success: (data) ->
      console.log "saved",data
      files[fn].odata=data
      editor.session.clearAnnotations()
      for k,v of files
        files[k].errs=null
      if data.data
        files[fn].data=data.data
        console.log "updated data after save"
        editor.setValue data.data
        editor.clearSelection()
        if files[fn].pos
          editor.navigateTo(files[fn].pos.row,files[fn].pos.column)
        else
          editor.gotoLine(0);
        changes=0

      if not data.syntax
        if data.errs
          for fn,data of data.errs
            a=[]
            for e in data
              if e.type=="error"
                $("#rightcolumn").append "<font color='red'>#{fn} #{e.row}: #{e.txt}</font><br>"
              else
                $("#rightcolumn").append "<font color='white'>#{fn} #{e.row}: #{e.txt}</font><br>"
              a.push({row: e.row-1, column: 0, html:e.txt, type:e.type})
            ensure_file(fn)
            files[fn].errs=a
            if current==fn
              editor.session.setAnnotations(a);
      files[fn].syntax=data.syntax
      $("#status").html("saved #{fn}")
      git "diff"
      return
    error: (xhr, ajaxOptions, thrownError) ->
      alert thrownError
      return


parse_tree = (node,setExpansion) ->
  #console.log "parse_tree",node.title
  if node.data.fullpath==current
    #console.log "match!!!",node.title,node.extraClasses
    node.setActive(true)
  else
    node.setActive(false)
  if node.title
    c=""
    have_errs=false
    ensure_file(node.data.fullpath)
    if files[node.data.fullpath].open
      c+="changed"
    if files[node.data.fullpath].diffs and Object.keys(files[node.data.fullpath].diffs).length
      c+=" gits"
      console.log ">>",node.title,node.extraClasses,files[node.data.fullpath].diffs
    if files[node.data.fullpath].errs and Object.keys(files[node.data.fullpath].errs).length
      c+=" errs"
      have_errs=true
      node.makeVisible()
    if node.extraClasses!=c
      node.extraClasses=c
      #if have_errs
      #  node.makeVisible()
      node.render(true)

  if node.children
    if setExpansion
      if node.data.fullpath in open_folders
        node.setExpanded(true)
    else
      if node.isExpanded()
        open_folders.push node.data.fullpath
    #else
    #  node.setExpanded(false)
    #console.log "doin",node.data
    for child in node.children
      parse_tree child

tree_fix = (setExpansion) ->
  if not setExpansion
    open_folders=[]
    setExpansion=false
  v=$("#leftcolumn").fancytree("getTree")
  parse_tree v.rootNode,setExpansion
  v.rootNode.setExpanded(true)
  root=$("#leftcolumn").fancytree("getRootNode")
  root.sortChildren( null, true);
  console.log "fixin tree: #{setExpansion}",open_folders

undo_clear = ->
  editor.session.getUndoManager().reset()
  editor.session.getUndoManager().markClean()

open_file = (fn) ->
  console.log "OPEN FILE",fn
  save_current()
  if fn and files[fn]
    #console.log "open #{fn}, ",files
    #console.log editor
    editor.session.setValue(files[fn].data)
    editor.scrollToRow(files[fn].scroll_row)

    # editor.session.setAnnotations([{row: 0, column: 0, html:"tässä virhe on!", type:"error"}]);
    #doc = editor.session.getDocument()
    #a=doc.createAnchor(1,1)
    #a=doc.createAnchor(1,1)
    if files[fn].pos
      editor.navigateTo(files[fn].pos.row,files[fn].pos.column)
    else
      editor.gotoLine(0);
    editor.focus(0);
    undo_clear()
    if /\.[c|h|cpp]$/.test(fn)
      mode="c_cpp"
    else if /\.rb|Rantfile$/.test(fn)
      mode="ruby"
    else if /\.py$/.test(fn)
      mode="python"
    else if /\.sh$/.test(fn)
      mode="shell"
    else if /\.json$/.test(fn)
      mode="json"
     else if /\.haml$/.test(fn)
      mode="haml"
     else if /\.md$/.test(fn)
      mode="markdown"
    else if /\.coffee$/.test(fn)
      mode="coffee"
    else if /\.js$/.test(fn)
      mode="javascript"
    else if /\.css$/.test(fn)
      mode="css"
    else
      mode="asciidoc"
    editor.getSession().setMode("ace/mode/#{mode}");
    #modelist = ace.require('ace/ext/modelist')
    #console.log "ml:",modelist
    current=fn
    $("#status").html("loaded #{current} as #{mode}")
    #console.log ("loaded #{current} as #{mode} -- changes zeroed")
    files[current].type=mode
    changes=0
    editor.setReadOnly(false)

    if files[fn].errs
      editor.session.setAnnotations(files[fn].errs);
    else
      editor.session.setAnnotations([]);

    tree_fix()
  else
    editor.session.setValue("")
    #editor.gotoLine(1);
    #editor.focus(1);

    editor.setReadOnly(true)
  update_tabs()
  undo_clear()
  git "diff"
  return null

update_tabs = ->
  s=""
  cnt=0
  for k,v of files
    if v.open
      cnt+=1
  tw=editor_width*0.90/cnt
  if tw>250
    tw=250
  else
    tw=Math.floor(tw)
  tabchars=Math.floor(tw/12)
  for k,v of files
    if not v.open
      continue
    kk=k[pro.length+1 ... k.length]
    if kk.length>tabchars
      ss=kk[0 ... tabchars]+".."
    else
      ss=kk
    c=""
    if k==current
      c="active"
    if files[k].diffs and Object.keys(files[k].diffs).length
      c+=" gits"
    t="<a onclick=\"loader('#{k}',true);return(false);\" title='#{kk}'>#{ss}</a>"
    t2="<a onclick=\"close_file('#{k}');return(false);\">X</a>"
    s="<li class='tabit #{c}'><span>#{t}</span> <span class='closer' style='color:red'>#{t2}</span></li>"+s
  s="<ul>#{s}</ul>"
  $("#tabs").html(s)
  $(".tabit").css('width', tw)
  #$(".tab").click (event) ->
  #console.log "tabi:",s

@loader = (fn,show) ->
  console.log "LOADER",fn

  if files[fn] and files[fn].open  and files[fn].data
    if show
      open_file(fn)
    return
  data=
    act: "load"
    fn: fn
    session: session
  #console.log "loader",fn,data
  $.ajax
    url: "/demo.json"
    type: "POST"
    data: data
    dataType: "json",
    contentType: "application/json; charset=utf-8",
    success: (data) ->
      #console.log data
      if data.note
        note data.note
      if data.alert
        alert data.alert
      ensure_file fn
      files[fn].data=data.data
      files[fn].odata=data.data
      files[fn].valid=true
      files[fn].open=true
      console.log "LOADER AFTER AJAX",fn
      changes=0
      if show
        open_file(fn)
      return
    error: (xhr, ajaxOptions, thrownError) ->
      alert thrownError
      return
  return

save_current = ->
  if current
    pos=editor.getCursorPosition()
    if changes>0 or pos.row>0 or pos.column>0
      files[current].pos=pos
      console.log "got pos:",files[current].pos,current
      files[current].scroll_row=editor.getFirstVisibleRow()
    if changes>0 and files[current].valid
      console.log "save_current,",current,changes
      files[current].data=editor.getValue()
      saver current,files[current].data
      changes=0
    ##matter of taste...undo_clear()

myTimer = ->
  if current and changes>0 and last_change>0 and last_change<(new Date).getTime()-2000
    save_current()
  if current
    $(".current").show()
    $(".nocurrent").hide()
  else
    $(".current").hide()
    $(".nocurrent").show()
  if pro
    $(".pro").show()
    $(".nopro").hide()
  else
    $(".pro").hide()
    $(".nopro").show()
  #tree_fix()

resizer = ->
  w=$(window).width()
  h=$(window).height()
  $("#leftmenu").width(margin)
  $("#leftcolumn").width(margin)
  $("#leftcolumn").height(h-menu-20)

  $("#cbot").width(marginr-6)
  $("#rightcolumn").width(marginr)
  $("#rightcolumn").height(h-menu-25)
  $("#navigation").height(menu)

  $("#content").css('top', menu)
  $("#content").css('left', margin)

  editor_width=w-margin-marginr
  $("#cmenu").width(editor_width)
  $("#editor").width(editor_width)
  $("#editor").height(h-menu-30-20-5)
  #console.log "resized to #{w},#{h}"
  update_tabs()

@close_file = (fn) ->
  if fn
    if fn==current
      save_current
    files[fn].open=false
    if files=={}
      current=null
      update_tabs()
    else if fn==current
      current=null
      for k,v of files
        if v.open
          current=k
          break
      open_file(current)
    else
      update_tabs()
    update_tabs()
    tree_fix()

show_diffs = ->
  len=editor.getSession().getLength()
  for row in [0 ... len]
    editor.getSession().removeGutterDecoration(row, "gitplus")
    editor.getSession().removeGutterDecoration(row, "gitminus")
    editor.getSession().removeGutterDecoration(row, "gitchange")
  if current and files[current].diffs
    for line,change of files[current].diffs
      if change=="+"
        editor.getSession().addGutterDecoration(line-1,"gitplus")
      else if change=="-"
        editor.getSession().addGutterDecoration(line-1,"gitminus")
      else
        editor.getSession().addGutterDecoration(line-1,"gitchange")


@git = (act) ->
  console.log "git #{act} #{pro}"
  if pro
    if act=="diff" and not current
      return
    if act=="delete" and not current
      return
    $.ajax(
      url: "/demo.json"
      data:
        act: "git"
        subact: act
        session: session
        path: pro
        fn: current
    ).done((result) ->
      console.log "git got: #{act} ->",result
      if result.alert
        alert result.alert
      if result.note
        note result.note

      if act=="diff_all"
        for fn,data in files
          files[fn].diffs={}
        show_diffs current
      else if act=="diff"
        files[current].diffs={}
        show_diffs current
      if result.diffs
        for fn,diffs of result.diffs
          ensure_file(fn)
          files[fn].diffs=diffs
          if fn==current
            show_diffs current
        tree_fix()
        update_tabs()
      if act=="checkout" or act=="commit"
        delete files[current] #reverting.. reload
        fn=current
        current=null
        loader fn,true
        current=fn
      else if act=="clone" or act=="pull" or act=="commit_all" or act=="delete"
        init_editor pro
      return
    ).fail((result) ->
      return
    ).always ->
      return

@init_editor  = (project)->

  if pro
    tree_fix() #pick up open folders...
    save_current()
    #save old files to browser
    for fn,data of files
      files[fn].data=null
      files[fn].odata=null
      files[fn].valid=false
    state={current: current, files: files, open_folders: open_folders}
    localStorage.setItem(pro, JSON.stringify(state))
  changes=0
  last_change=0
  files={}
  open_folders=[]
  current=null
  if project and localStorage.getItem(project)
    state=JSON.parse(localStorage.getItem(project));
    files=state.files||{}
    for fn,data of files
      files[fn].diffs=[]

    open_folders=state.open_folders||[]
    current=state.current||null
    #console.log "loaded storage",state
    #console.log "current",current,files[current].pos,files[current].pos.row
  if project
    ajax({act: "dir", project: project , open_folders: open_folders})
  else
    ajax({act:"flatdir", owner:userid} )
  pro=project
  editor.session.setValue("")
  editor.getSession().setTabSize(2)
  editor.getSession().setUseSoftTabs(true)
  editor.clearSelection()
  editor.gotoLine(0)
  editor.focus(0)
  editor.setOptions({fontSize: "9pt"})
  editor.setTheme("ace/theme/vibrant_ink");
  editor.commands.addCommand
    name: "mySave"
    bindKey:
      win: "Ctrl-S"
      mac: "Command-S"
    exec: (editor) ->
      save_current()

    readOnly: true

  editor.commands.addCommand
    name: "myClose"
    bindKey:
      win: "Ctrl-Q"
      mac: "Command-Q"
    exec: (editor) ->
      close_file(current)

    readOnly: true

  editor.commands.addCommand
    name: "myReload"
    bindKey:
      win: "Ctrl-R"
      mac: "Command-R"
    exec: (editor) ->
      if current
        delete files[current]
        fn=current
        current=null
        loader fn,true
        current=fn
      console.log "reload"

    readOnly: true

  editor.commands.addCommand
    name: "myGo"
    bindKey:
      win: "Ctrl-G"
      mac: "Command-G"
    exec: (editor) ->
      if current
        console.log "GO!"
        $.ajax(
          url: "/demo.json"
          data:
            act: "go"
            session: session
            path: pro
            fn: current
        ).done((result) ->
          return
        ).fail((result) ->
          return
        ).always ->
          return

    readOnly: true
  editor.commands.addCommand
    name: "myGoStop"
    bindKey:
      win: "Shift-Ctrl-G"
      mac: "Shift-Command-G"
    exec: (editor) ->
      if current
        console.log "STOP!"
        $.ajax(
          url: "/demo.json"
          data:
            act: "stop"
            session: session
            fn: current
        ).done((result) ->
          return
        ).fail((result) ->
          return
        ).always ->
          return

    readOnly: true

  if project
    for fn,data of files
      if files[fn].open
        loader fn,current==fn
        if not current
          current=fn

  update_tabs()
  console.log "OPENED current ",current
  open_file(current)

  editor.on "change", (e) ->
    if current
      changes+=1
      last_change=(new Date).getTime()
      $("#status").html("#{current} changes #{changes}")
      #console.log "changes #{current} #{changes}"
      #console.log ("#{current} changes #{changes}")
    #if e.data.action=="insertText"
    #  for x in [e.data.range.start.row .. e.data.range.end.row]
    #    console.log ">",x
    #    editor.session.addGutterDecoration(x,"changed")
    #else
      #console.log "??",e.data.action,e
  #document.getElementById('editor').style.fontSize='12px';
  undo_clear()



@stm_port = (act,val) ->
  console.log "port #{act},#{val}"
  if true
    $.ajax(
      url: "http://20.20.20.21:8087/demo.json"
      data:
        act: act
        val: val
        session: session
    ).done((result) ->
      console.log "stm got: #{act} ->",result
      return
    ).fail((result) ->
      return
    ).always ->
      return

$ ->
  console.log "Script Starts..."
  stream = new EventSource("/sse_demo.json")
  stream.addEventListener "message", (event) ->
    sse_data('',$.parseJSON(event.data))
    return
  streamc = new EventSource("http://20.20.20.21:8087/sse_demo.json")
  streamc.addEventListener "message", (event) ->
    console.log "korteksi:",$.parseJSON(event.data)
    sse_data('$',$.parseJSON(event.data))
    return

  editor = ace.edit("editor");
  editor.setTheme("ace/theme/textmate")
  init_editor(null)
  $(window).resize ->
    resizer()
  resizer()
  setInterval(->
    myTimer()
    return
  , 100)

  document.addEventListener "keydown", ((evt) ->
    #console.log "key",evt
    if evt.ctrlKey
      stopEvilCtrlW = (e) ->
        "Oopsies, Chrome!"

      clearEvilCtrlW = ->
        window.removeEventListener "beforeunload", stopEvilCtrlW, false
        return
      setTimeout clearEvilCtrlW, 1000
      window.addEventListener "beforeunload", stopEvilCtrlW, false
    return
  ), false

  return null




