# Play an HLS stream.
# @category Source / Input
# @param ~id Force the value of the source ID.
# @param ~reload How often (in seconds) the playlist should be reloaded.
# @param uri Playlist URI
def input.hls(~id="",~reload=10.,uri)
  playlist = ref []
  sequence = ref 0
  playlist_uri = ref uri

  def load_playlist () =
    pl = request.create.raw(!playlist_uri)
    if request.resolve(pl) then
      pl = request.filename(pl)

      m = string.extract(pattern="#EXT-X-MEDIA-SEQUENCE:(\\d+)",file.contents(pl))
      pl_sequence = list.assoc(default="","1",m)
      log.info(label=id,"Sequence: " ^ pl_sequence)
      pl_sequence = int_of_string(default=0,pl_sequence)

      files = playlist.parse(path=path.dirname(!playlist_uri)^"/",pl)

      def file_request(idx,el) =
        let (meta,file) = el
        s = list.fold(fun (cur, el) -> "#{cur},#{fst(el)}=#{string.escape(snd(el))}", "", meta)
        s = if s == "" then file else "annotate:#{s}:#{file}" end
        (pl_sequence+idx, s)
      end

      files = list.mapi(file_request,files)

      let (first_idx, _) = list.hd(default=(-1,""),!playlist)

      def add_file(playlist, file) =
        let (idx,_) = file
        if first_idx < idx and not list.mem_assoc(idx, playlist) then
          list.append(playlist, [file])
        else
          playlist
        end
      end

      playlist := list.fold(add_file, !playlist, files)
    else
      log.severe(label=id,"Couldn't read playlist: request resolution failed.")
      playlist := []
    end
    request.destroy(pl)
    reload
  end

  def rec next () =
    file =
      if list.length(!playlist) > 0 then
        let (_,ret) = list.hd(default=(1,""),!playlist)
        playlist := list.tl(!playlist)
        sequence := !sequence + 1
        ret
      else
        ""
      end
    request.create(file)
  end

  def find_stream () =
    pl = request.create.raw(!playlist_uri)
    if request.resolve(pl) then
      plfile = request.filename(pl)

      m = string.extract(pattern="#EXT-X-STREAM-INF[^\\n]*\\n([^\\r\\n]*)\\r?\\n",file.contents(plfile))
      playlist_uri := list.assoc(default=!playlist_uri,"1",m)

      if not (string.contains(substring="/", !playlist_uri)) then
        playlist_uri := path.dirname(request.uri(pl)) ^ "/" ^ !playlist_uri
      end
      log(label=id,"Playlist: " ^ !playlist_uri)
    end
  end
  find_stream ()

  source = request.dynamic(id=id,default_duration=0.5,length=5.,next)

  source = merge_tracks(source)

  add_timeout(0., load_playlist)

  source
end

# @flag hidden
def output.harbor.hls.base(~id,~fallible,~on_start,~on_stop,
                           ~playlist,~segment_name,~segment_duration,
                           ~segments,~segments_per_playlist,
                           ~start,~port,~path,serve,formats,s)
  tmp_dir = file.temp_dir("hls","")

  def content_type(file) =
    ext = file.extension(file)
    if ext == ".m3u8" then
      "application/x-mpegURL"
    else
      def f(cur,el) =
        format = snd(el)
        if ext == ".#{encoder.extension(format)}" then
          encoder.content_type(format)
        else
          cur
        end
      end
      list.fold(f,"",formats)
    end
  end

  serve(port=port,path=path,content_type=content_type,tmp_dir)

  output.file.hls(id=id,fallible=fallible,on_start=on_start,on_stop=on_stop,
                  playlist=playlist,start=start,segment_name=segment_name,
                  segment_duration=segment_duration,segments=segments,
                  segments_per_playlist=segments_per_playlist,tmp_dir,formats,s)
end

# Output the source stream to an HTTP live stream served from the harbor HTTP server.
# @category Source / Output
# @param ~id Force the value of the source ID.
# @param ~fallible Allow the child source to fail, in which case the output will be (temporarily) stopped.
# @param ~on_start Callback executed when outputting starts.
# @param ~on_stop Callback executed when outputting stops.
# @param ~playlist Playlist name (m3u8 extension is recommended).
# @param ~segment_duration Segment duration (in seconds).
# @param ~segment_name Segment name. Default: `fun (~position,~extname,stream_name) -> "#{stream_name}_#{position}.#{extname}"`
# @param ~segments Number of segments to keep.
# @param ~segments_per_playlist Number of segments per playlist.
# @param ~start Automatically start outputting whenever possible. If true, an infallible (normal) output will start outputting as soon as it is created, and a fallible output will (re)start as soon as its source becomes available for streaming.
# @param ~port Port for incoming harbor (http) connections.
# @param ~headers Default response headers.
# @param ~path Base path for hls URIs.
# @param formats List of specifications for each stream: (name, format).
def output.harbor.hls(~id="",~fallible=false,~on_start={()},~on_stop={()},
                      ~segment_duration=10.,~segments=15,~segments_per_playlist=10,
                      ~segment_name=(fun (~position,~extname,stream_name) -> "#{stream_name}_#{position}.#{extname}"),
                      ~start=true,~playlist="stream.m3u8",~port=8000,~path="/",
                      ~headers=[("Access-Control-Allow-Origin","*")],formats,s)
  def serve(~port,~path,~content_type,dir) =
    harbor.http.static(port=port,path=path,content_type=content_type,headers=headers,dir)
  end
  output.harbor.hls.base(id=id,fallible=fallible,on_start=on_start,on_stop=on_stop,
                         segment_duration=segment_duration,segments=segments,
                         segments_per_playlist=segments_per_playlist,segment_name=segment_name,
                         start=start,port=port,path=path,playlist=playlist,
                         serve,formats,s)
end

%ifdef harbor.https.static
# Output the source stream to an HTTP live stream served from the harbor HTTPS server.
# @category Source / Output
# @param ~id Force the value of the source ID.
# @param ~fallible Allow the child source to fail, in which case the output will be (temporarily) stopped.
# @param ~on_start Callback executed when outputting starts.
# @param ~on_stop Callback executed when outputting stops.
# @param ~playlist Playlist name (m3u8 extension is recommended).
# @param ~segment_duration Segment duration (in seconds).
# @param ~segment_name Segment name. Default: `fun (~position,~extname,stream_name) -> "#{stream_name}_#{position}.#{extname}"`
# @param ~segments Number of segments to keep.
# @param ~segments_per_playlist Number of segments per playlist.
# @param ~start Automatically start outputting whenever possible. If true, an infallible (normal) output will start outputting as soon as it is created, and a fallible output will (re)start as soon as its source becomes available for streaming.
# @param ~port Port for incoming harbor (https) connections.
# @param ~headers Default response headers.
# @param ~path Base path for hls URIs.
# @param formats List of specifications for each stream: (name, format).
def output.harbor.hls.https(~id="",~fallible=false,~on_start={()},~on_stop={()},
                            ~segment_duration=10.,~segments=15,~segments_per_playlist=10,
                            ~segment_name=(fun (~position,~extname,stream_name) -> "#{stream_name}_#{position}.#{extname}"),
                            ~port=8000,~path="/",~headers=[("Access-Control-Allow-Origin","*")],
                            ~start=true,~playlist="stream.m3u8",formats,s)
  def serve(~port,~path,~content_type,dir) =
    harbor.https.static(port=port,path=path,content_type=content_type,headers=headers,dir)
  end
  output.harbor.hls.base(id=id,fallible=fallible,on_start=on_start,on_stop=on_stop,
                         segment_duration=segment_duration,segments=segments,
                         segments_per_playlist=segments_per_playlist,segment_name=segment_name,
                         start=start,port=port,path=path,playlist=playlist,
                         serve,formats,s)
end
%endif
