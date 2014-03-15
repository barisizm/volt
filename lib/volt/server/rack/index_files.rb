require 'volt/server/rack/asset_files'
require 'volt/router/routes'

# Serves the main pages
class IndexFiles
  def initialize(app, component_paths, opal_files)
    @app = app
    @component_paths = component_paths
    @opal_files = opal_files

    @@router ||= Routes.new.define do
      # Find the route file
      home_path = component_paths.component_path('main')
      route_file = File.read("#{home_path}/config/routes.rb")
      eval(route_file)
    end
  end

  def route_match?(path)
    params = @@router.url_to_params(path)

    return params if params

    return false
  end

  def call(env)
    if route_match?(env['PATH_INFO'])
      [200, { 'Content-Type' => 'text/html; charset=utf-8' }, [html]]
    else
      @app.call env
    end
  end

  def html
    index_path = File.expand_path(File.join(Volt.root, "public/index.html"))
    html = File.read(index_path)

    ERB.new(html).result(binding)
  end

  def javascript_files
    # TODO: Cache somehow, this is being loaded every time
    AssetFiles.new('main', @component_paths).javascript_files(@opal_files)
  end

  def css_files
    AssetFiles.new('main', @component_paths).css_files
  end



end


