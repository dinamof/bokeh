_ = require "underscore"
{logger} = require "../../common/logging"
HasParent = require "../../common/has_parent"
PlotWidget = require "../../common/plot_widget"
FactorRange = require "../../range/factor_range"
RemoteDataSource = require "../../source/remote_data_source"

class GeoJSONRendererView extends PlotWidget

  initialize: (options) ->
    super(options)

    @point = @build_glyph_view(@mget("point"))
    @line = @build_glyph_view(@mget("line"))
    @polygon = @build_glyph_view(@mget("polygon"))

    @xmapper = @plot_view.frame.get('x_mappers')[@mget("x_range_name")]
    @ymapper = @plot_view.frame.get('y_mappers')[@mget("y_range_name")]

    @set_data(false)

  build_glyph_view: (model) ->
    new model.default_view({model: model, renderer: this})

  bind_bokeh_events: () ->
    @listenTo(@model, 'change', @request_render)
    @listenTo(@mget('data_source'), 'change', @set_data)
    @listenTo(@mget('data_source'), 'select', @request_render)

  have_selection_glyphs: () -> false

  # TODO (bev) arg is a quick-fix to allow some hinting for things like
  # partial data updates (especially useful on expensive set_data calls
  # for image, e.g.)
  set_data: (request_render=true, arg) ->
    t0 = Date.now()
    source = @mget('geojson')

    @circle.set_data(source, arg)
    @circle.set_visuals(source)

    length = source.get_length()
    length = 1 if not length?
    @all_indices = [0...length]

    dt = Date.now() - t0
    @set_data_timestamp = Date.now()
    if request_render
      @request_render()

  render: () ->
    t0 = Date.now()
    
    glsupport = @glyph.glglyph
    
    tmap = Date.now()
    @glyph.map_data()
    dtmap = Date.now() - t0

    tmask = Date.now()
    if glsupport
      indices = @all_indices  # WebGL can do the clipping much more efficiently
    else
      indices = @glyph._mask_data(@all_indices)
    dtmask = Date.now() - tmask

    ctx = @plot_view.canvas_view.ctx
    ctx.save()

    selected = @mget('data_source').get('selected')
    if !selected or selected.length == 0
      selected = []
    else
      if selected['0d'].flag
        selected = indices
      else if selected['1d'].indices.length > 0
        selected = selected['1d'].indices
      else if selected['2d'].indices.length > 0
        selected = selected['2d'].indices
      else
        selected = []

    lod_threshold = @plot_model.get('lod_threshold')
    if @plot_view.interactive and !glsupport and lod_threshold? and @all_indices.length > lod_threshold
      # Render decimated during interaction if too many elements and not using GL
      indices = @decimated
      glyph = @decimated_glyph
      nonselection_glyph = @decimated_glyph
      selection_glyph = @selection_glyph
    else
      glyph = @glyph
      nonselection_glyph = @nonselection_glyph
      selection_glyph = @selection_glyph

    if not (selected.length and @have_selection_glyphs())
      trender = Date.now()
      glyph.render(ctx, indices, @glyph)
      dtrender = Date.now() - trender

    else
      # reset the selection mask
      tselect = Date.now()
      selected_mask = {}
      for i in selected
        selected_mask[i] = true

      # intersect/different selection with render mask
      selected = new Array()
      nonselected = new Array()
      for i in indices
        if selected_mask[i]?
          selected.push(i)
        else
          nonselected.push(i)
      dtselect = Date.now() - tselect

      trender = Date.now()
      nonselection_glyph.render(ctx, nonselected, @glyph)
      selection_glyph.render(ctx, selected, @glyph)
      dtrender = Date.now() - trender

    @last_dtrender = dtrender

    dttot = Date.now() - t0
    logger.debug("#{@glyph.model.type} GlyphRenderer (#{@model.id}): render finished in #{dttot}ms")
    logger.trace(" - map_data finished in       : #{dtmap}ms")
    if dtmask?
      logger.trace(" - mask_data finished in      : #{dtmask}ms")
    if dtselect?
      logger.trace(" - selection mask finished in : #{dtselect}ms")
    logger.trace(" - glyph renders finished in  : #{dtrender}ms")

    ctx.restore()

  map_to_screen: (x, y) ->
    @plot_view.map_to_screen(x, y, @mget("x_range_name"), @mget("y_range_name"))

  draw_legend: (ctx, x0, x1, y0, y1) ->
    @glyph.draw_legend(ctx, x0, x1, y0, y1)

  hit_test: (geometry) ->
    @glyph.hit_test(geometry)



class GeoJSONRenderer extends HasParent
  default_view: GeoJSONRendererView
  type: 'GeoJSONRenderer'

  selection_defaults: {}
  decimated_defaults: {fill_alpha: 0.3, line_alpha: 0.3, fill_color: "grey", line_color: "grey"}
  nonselection_defaults: {fill_alpha: 0.2, line_alpha: 0.2}

  defaults: ->
    return _.extend {}, super(), {
      x_range_name: "default"
      y_range_name: "default"
      data_source: null
    }

  display_defaults: ->
    return _.extend {}, super(), {
      level: 'glyph'
    }


module.exports =
  Model: GeoJSONRenderer
  View: GeoJSONRendererView
