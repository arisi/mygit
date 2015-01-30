# encode: UTF-8

require 'pathname'
require 'curb'

def directory_hash(path, name=nil,open_folders=[])
  data = {:title => (name || path), fullpath: path, folder: true}
  data[:children] = children = []
  Dir.foreach(path) do |entry|
    next if (entry == '..' || entry == '.' || entry == '.git' || entry == 'bin'|| entry == 'build'|| entry[/~/])
    full_path = File.join(path, entry)
    if File.directory?(full_path)
      expanded=open_folders.include? full_path
      puts "check #{open_folders},#{full_path},#{expanded}"
      children << directory_hash(full_path, entry,open_folders).merge(folder: true, tooltip: full_path,expanded:expanded)
    else
      children <<  {title: entry, fullpath: path+"/"+entry, tooltip: path+"/"+entry}
    end
  end
  return data
end

def directory_flat(path)
  data = {:title => path, fullpath: path, folder: true,expanded: true}
  data[:children] = children = []
  Dir.foreach(path) do |entry|
    next if (entry == '..' || entry == '.' || entry == '.git')
    full_path = File.join(path, entry)
    if File.directory?(full_path)
      children << {title: entry, fullpath: path+"/"+entry,folder: true}
    end
  end
  return data
end

def json_demo request,args,session,event
  begin
    session=args['session'].to_i
    #return ["text/json",{alert: "Error: No Session! Reload page!"}] if session<1 or not $sessions[session] #fix this ...
    alert=nil
    puts "ok: #{args}"
    if args['act']=='dir'
      project=args['project']
      open_folders=args['open_folders']||[]
      puts "**************************** open_folders: #{open_folders}"
      f={dir: [directory_hash(project,"",open_folders)]}
      $sessions[session][:queue] << "Loaded Project #{project}\n" if $sessions[session] #sse may not be inited yet... move this to minimal...
      $sessions.each do |s,d|
        d[:queue] << "** #{session} Loaded Project #{project}\n" #broadcast
      end
    elsif args['act']=='flatdir'
      owner=args['owner']
      if not File.directory? owner
         Dir.mkdir owner
      end
      require "github_api"
      x= Github.new basic_auth: 'arisi:Juzzi067'
      pp x
      r= x.repos.list user: owner
      r.each do |k,repo|
        path="#{owner}/#{k.name}"
        if File.directory? path
          puts "on jo #{k.name}"
        else
          url="https://github.com/#{owner}/#{k.name}"
          puts "haetaan... #{path} : #{url} -> #{owner}"
          Dir.mkdir "#{path}"
          #ret=`cd #{owner}; git clone #{url}`
        end
      end
      #let's get all stuff from github :)
      f={flatdir: [directory_flat("#{owner}")]}
      $sessions[session][:queue] << "Loaded Projects for #{owner}\n" if $sessions[session]
    elsif args['act']=='git'
      subact=args['subact']
      path=args['path']
      fn=args['fn']
      $sessions[session][:queue] << "GIT: #{subact} #{path}:" if  $sessions[session]
      url="git@github.com:#{path}"
      if subact=='make_build' #increment build number
        cnt=1
        begin
          s = IO.read("#{path}/build.cnt")
          puts "read #{s}"
          cnt=s.to_i
        rescue
          cnt=1
        end
        puts "-> #{cnt}"
        cnt+=1
        f=File.open("#{path}/build.cnt","w")
        f.write("#{cnt}\n")
        f.close()
        f=File.open("#{path}/build.def","w")
        f.write("#{cnt}")
        f.close()
        puts "BUILDER!!!!!!!!! #{path} => #{cnt}"
        return ["text/json",{alert: "BUILDING : #{cnt}"}]
      elsif subact=='indev' #dev builds now
        puts "INDEV!!!!!!!!! #{path}"
        f=File.open("#{path}/build.def","w")
        f.write("0")
        f.close()
        return ["text/json",{alert: "INDEV"}]
      elsif subact=='clone'
        cmd="git #{subact} #{url} #{path}"
      elsif subact=='delete' #not acatually git stuf...
        if File.file? fn
          puts "delete #{fn} ..."
          FileUtils.rm fn
        else
          puts "delete #{fn} .. does not exist"
        end
        return ["text/json",{}]
      elsif subact=="checkout"
        file=fn[path.size+1 ... fn.size]
        cmd="chdir #{path}; git #{subact} #{file}"
      elsif subact=="diff_all"
        cmd="chdir #{path}; git diff origin/master"
      elsif subact=="diff"
        file=fn[path.size+1 ... fn.size]
        cmd="chdir #{path}; git diff origin/master -- #{file}"
      elsif subact=="commit_all"
        msg="fixes"
        cmd="chdir #{path}; git add --all; git commit -m '#{msg}'; git push origin master"
      elsif subact=="status"
        cmd="chdir #{path}; git fetch origin;git diff origin/master; echo '*END'; git #{subact}"
      elsif subact=="commit"
        msg="fix"
        file=fn[path.size+1 ... fn.size]
        cmd="chdir #{path}; git add #{file}; git commit -m '#{msg}'; git push origin master"
      else
        cmd="chdir #{path}; git #{subact}"
      end
      puts "************** ABOUT TO GIT:"
      puts cmd
      lines=`#{cmd} 2>&1`.split("\n")
      f={}
      if subact=='diff' or subact=="diff_all" or subact=="status"
        mode=:idle
        c=0
        rec={}
        diffs={}
        file=""
        lines.each do |line|
          if line[/Your branch is behind '(.+)' by (\d+) comm/]
            #puts "CONFLICTS: #{$2}"
            alert="NOTE: Repository has changed, #{$2} Commits !!!\nPlease PULL ASAP!!!"
          elsif line[/have diverged/]
            #puts "CONFLICTS: #{$2}"
            alert="NOTE: Repository has diverged!!!\nPlease PULL And Fix conflicts, Then COMMIT ASAP!!!"
          elsif line[/Untracked files:/]
            #puts "CONFLICTS: #{$2}"
            alert="NOTE: You have untracked files!!! COMMIT ASAP!!"
            mode=:untracked
          elsif mode==:untracked and line[/\t(.+)/]
            file="#{path}/#{$1}"
            puts "UNTRACKED: #{file} ***************************************************************************"
            $sessions[session][:queue] << "********** UNTRACKED #{file}"
            diffs[file]={}
            diffs[file][1]="U"
          elsif line[/modified:   (.+)/]
            file="#{path}/#{$1}"
            puts "MODIFIED: #{file}"
          elsif line[/--- a\/(.+)/]
            file="#{path}/#{$1}"
            puts "FILE::: #{file}"
            diffs[file]={}
          elsif line[/@@ -(\d+),(\d+) \+(\d+),(\d+) @@/]
            #$sessions[session][:queue] << "@@:: #{$1},#{$2},#{$3},#{$4}"
            #puts "@@ #{line}"
            mode=:diff
            rec={from: $1.to_i, len: $2.to_i, new_from: $3.to_i, new_len: $4.to_i}
            c=0
          elsif line[/@@ -(\d+),(\d+) \+(\d+) @@/]
            #$sessions[session][:queue] << "@@:: #{$1},#{$2},#{$3}"
            #puts "@@ #{line}"
            mode=:diff
            rec={from: $1.to_i, len: $2.to_i, new_from: $3.to_i, new_len: 1}
            c=0
          elsif line[/@@ -(\d+) \+(\d+),(\d+) @@/]
            #$sessions[session][:queue] << "@@:: #{$1},#{$2},#{$3}"
            #puts "@@ #{line}"
            mode=:diff
            rec={from: $1.to_i, len: 1, new_from: $2.to_i, new_len: $3.to_i}
            c=0
          elsif line[/@@ -(\d+) \+(\d+) @@/]
            #$sessions[session][:queue] << "@@:: #{$1},#{$2}"
            #puts "@@ #{line}"
            mode=:diff
            rec={from: $1.to_i, len: 1, new_from: $2.to_i, new_len: 1}
            c=0
          elsif mode==:diff and
            change=line[0]
            if change=="*"
              mode=:idle
              next
            end
            if change!=" "
              #$sessions[session][:queue] << "DD::#{rec[:from]}+#{c}=#{rec[:from]+c}/#{rec[:len]} #{change}"
              if diffs[file][rec[:from]+c]
                diffs[file][rec[:from]+c]="C"
              else
                diffs[file][rec[:from]+c]=change
              end
            end
            #puts "DD #{line}"
            if change!="-"
              c+=1
            end
          end
        end
        pp diffs
        f={diffs: diffs,alert: alert}
      end
      lines.each do |line|
        $sessions[session][:queue] << "#{line}"
        puts line
      end
    elsif args['act']=='stop'
      if $sessions[session][:thread] and $sessions[session][:thread].status
        $sessions[session][:queue] << "Stopping old thread!"
        $sessions[session][:thread].kill
      else
        $sessions[session][:queue] << "Nothing running!"
        f={alert: "We already have runnin thread!"}
      end
    elsif args['act']=='go'
      fn=args['fn']
      path=args['path']
      if File.file? "#{path}/compile.sh"
        $sessions[session][:queue] << "Flashing... #{fn}\n"
        http = Curl::Easy.http_get("http://20.20.20.21:8087/demo.json?act=flash") do |http|
          http.verbose = true
        end
        $sessions[session][:queue] << "Running #{fn}\n"
      else
        pn = Pathname.new(fn)
        full=File.expand_path fn
        fullp=File.expand_path path
        puts "go: #{fn} @ #{pn.dirname} cmd: #{pn.basename} full=#{full} fpath=#{fullp}"
        if $sessions[session][:thread] and $sessions[session][:thread].status
          $sessions[session][:queue] << "We already have runnin thread!"
          f={alert: "We already have runnin thread!"}
        else
          t=Thread.new(session) do |session|
            puts "thread: #{pn.basename}"
            IO.popen("chdir #{fullp}; ruby #{full} 2>&1 ; echo retval=$?").each do |line|
              puts "got line from #{pn.basename}"
              p line.chomp
              if line[/(.+):(\d+): (.+)/]
                $sessions[session][:queue] << "ERROR: #{$2} #{$3}"#{row: $2, txt: $3}
              end
              $sessions[session][:queue] << line.chomp
            end
            $sessions[session][:queue] << "thread: #{pn.basename} exits"
          end
          $sessions[session][:thread]=t
          $sessions[session][:queue] << "Running #{fn}\n"
          f={}
        end
      end
    elsif args['act']=='load'
      fn=args['fn']
      if fn[/\.[c|cpp]$/] or fn[/\.h$/]
        cmd="uncrustify -f #{fn} -o #{fn} -c uncrustify.conf"
        system cmd
      end
      puts "loading #{fn}"
      begin
        f={data: File.open(fn, "r:UTF-8").read}
        $sessions[session][:queue] << "Loaded #{fn}\n"
      rescue Exception => e
        f={data: "\n", note: "File Not Found: #{fn} -- Start from Scratch!"}
        $sessions[session][:queue] << "NOT Loaded #{fn} -- does not exist\n"
      end
    elsif args['act']=='rename'
      fn=args['fn']
      newname=args['newname']
      folder=args['folder']
      pn = Pathname.new(fn)
      fullname="#{pn.dirname}/#{newname}"
      puts "rename: #{fn},#{newname},#{folder}"
      if not folder and not File.file? fn and not File.file? fullname #none exist -- assume never saved new file
        puts "new file..."
        f={fullpath: fullname,fn: newname}
        pp f
      elsif folder and not File.directory? fn and not File.directory? fullname #none exist -- assume never saved new file
        puts "new dir..."
        puts "creating dir #{fullname}"
        FileUtils.mkdir_p fullname
        f={fullpath: fullname,fn: newname}
        pp f
      elsif not folder and not File.file? fn and File.file? fullname #orig does exist -- target exist -- nodo!
        puts "already f exists..."
        f={err: "Target File Already Exists!"}
      elsif folder and not File.directory? fn and File.directory? fullname #orig does exist -- target exist -- nodo!
        puts "already d exists..."
        f={err: "Target Directory Already Exists!"}
      else
        puts "renaming '#{fn}' to '#{fullname}'"
        begin
          File.rename fn,fullname
          f={fullpath: fullname,fn: newname}
          $sessions[session][:queue] << "renamed '#{fn}' to '#{fullname}'"
        rescue =>e
          f={err: "#{e}"}
        end
      end
    elsif args['act']=='save'
      fn=args['fn']
      data=args['data']
      type=args['type']
      path=args['path']
      pn = Pathname.new(fn)
      if not File.directory? pn.dirname
        puts "creating dir #{pn.dirname}"
        FileUtils.mkdir_p pn.dirname
      end
      puts "SAVE #{fn} : '#{data}'"
      File.open(fn, "w:UTF-8") do |file|
        file.write(data)
      end
      check=""
      ok=true
      errs={}
      newdata=nil
      if File.file? "#{path}/compile.sh"
        begin
          $sessions[session][:queue] << "WE HAVE COMPILE SCRIPT #{fn} "
          check=`cd #{path};./compile.sh x sol `.force_encoding("UTF-8")
          puts "check: '#{check}'"
          begin
            l=check.split("\n")
          rescue => e
            puts e
            pp e.backtrace
            return ["text/json",{alert: "error #{e}"}]
          end

          l.each do |r|
            puts "line: '#{r}'"
            if r[/In file included from (.+):(\d+):(\d+):/]
              file="#{path}/#{$1}"
              errs[file]=[] if not errs[file]
              errs[file]<< {row: $2, type: :error, txt: "Included file Has Errors!"}
            elsif r[/(.+):(\d+):(\d+): fatal error: (.+)$/]
              file="#{path}/#{$1}"
              errs[file]=[] if not errs[file]
              errs[file]<< {fn: file, row: $2, type: :error, txt: $4}
            elsif r[/(.+):(\d+):(\d+): (.+): (.+)$/]
              file="#{path}/#{$1}"
              errs[file]=[] if not errs[file]
              errs[file]<< {fn: file, row: $2, type: $4, txt: $5}
            elsif r[/(.+):(\d+): undefined reference to (.+)$/]
              pwd=Dir.pwd
              #/home/arisi/projects/mygit/arisi/ctex_apps/src/appi.c:35: undefined reference to `xxx'
              row=$2
              sym=$3
              puts "********************* LINKER ERROR at #{row}"
              file=$1.sub("#{pwd}/","")
              errs[file]=[] if not errs[file]
              errs[file]<< {fn: file, row: row, type: :error, txt: "LINKER: undefined reference to `#{sym}'"}
            end
          end
          ok=false if errs!={}
          pp errs
        rescue => e
          puts e
          pp e.backtrace
          return ["text/json",{alert: "error #{e}"}]
        end

      elsif type=="c_cpp"
        cmd="uncrustify -f #{fn} -o #{fn} -c uncrustify.conf"
        system cmd
        newdata= File.open(fn, "r:UTF-8").read

        file=fn[path.size+1 ... fn.size]
        cmd="cd #{path};gcc -c -Wall #{file} -o /dev/null"
        puts "c syntax test '#{cmd}'"
        check=`#{cmd} 2>&1`
        puts "check: '#{check}'"
        l=check.split("\n")
        l.each do |r|
          puts "line: '#{r}'"
          if r[/In file included from (.+):(\d+):(\d+):/]
            file="#{path}/#{$1}"
            errs[file]=[] if not errs[file]
            errs[file]<< {row: $2, type: :error, txt: "Included file '#{file}' Has Errors!"}
          elsif r[/(.+):(\d+):(\d+): fatal error: (.+)$/]
            file="#{path}/#{$1}"
            errs[file]=[] if not errs[file]
            errs[file]<< {fn: file, row: $2, type: :error, txt: $4}
          elsif r[/(.+):(\d+):(\d+): (.+): (.+)$/]
            file="#{path}/#{$1}"
            errs[file]=[] if not errs[file]
            errs[file]<< {fn: file, row: $2, type: $4, txt: $5}
          end
        end
        ok=false if errs!={}
      elsif type=="ruby"
        puts "exec 'ruby -c #{fn}'"
        check=`ruby -c #{fn} 2>&1`
        puts "check: '#{check}'"
        if not check[/Syntax OK/]
          ok=false
          check.split("/n").each do |r|
            puts "chec: '#{r}'"
            if r[/(.+):(\d+): (.+)/]
              errs[fn]=[] if not errs[file]
              errs[fn]<< {row: $2, type: :error, txt: $3}
            end
          end
        end
      end
      puts "saved #{fn}: #{fn} -> #{check}\n"
      pp errs
      f={save:ok, syntax: ok, errs: errs,data: newdata}
      $sessions[session][:queue] << "Saved #{fn} "
    else
      f=[]
    end
    return ["text/json",f]
  rescue => e
    pp e.backtrace
    return ["text/json",{alert: "error #{e}"}]
  end
end
