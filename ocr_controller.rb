require 'restclient'
require 'json'

class OcrController < ApplicationController
before_filter :autorizar_acceso

@@ignore_list = ['zip.rb','.','..','.svn','proc.rb','ocr.rb','ready','procesar_ocr.rb','manage.rb']
@@ruta =  "#{RAILS_ROOT}/public/files"

  def index
    @revistas_sin_ocr = Array.new()
    @revistas_en_progreso = Hash.new()
    @revistas_con_ocr = Array.new()
    @ruta_revistas = @@ruta
    tiempo_ahora = Time.now
    max_seg_mostrar = 3600 # en segundos
    
    revistas = Dir.entries(@@ruta)

    revistas.sort.each do |revista| # revista es cada carpeta dentro de la ruta de imagenes

      if !@@ignore_list.include? revista then # Para evitar tomar carpetas ignoradas

        # Solo revistas que no hayan sido terminadas o que no esten en proceso
        # Tambien las completadas dentro de hace menos de n dias
        if !File.exist?("#{@@ruta}/#{revista}/ocr_ready") and !File.exist?("#{@@ruta}/#{revista}/ocr_progress")
          @revistas_sin_ocr.push revista
        elsif File.exist?("#{@@ruta}/#{revista}/ocr_progress")
          progress_old = -1
          status = nil
          id = -1
          File.open("#{@@ruta}/#{revista}/ocr_progress","r") do |file|
            id = file.gets.to_i
            status = file.gets.strip
            progress_old = file.gets.to_i       
          end

          if status != "failed"
            progress = job_progress(id) # Consultando el progreso del job de la revista
          end
          
          if status == "failed" or progress[:valid] # La llamada fue exitosa o la tarea estaba marcada como failed
            # Si el job ya esta terminado se crea el ocr_ready
            if status != "failed" and progress[:percent] == 100 and progress[:status] == "succeeded"
              File.open("#{@@ruta}/#{revista}/ocr_ready","w")

              # Tambien eliminaremos el ocr_progress ya que no es necesario ahora
              File.delete("#{@@ruta}/#{revista}/ocr_progress")
              
              #Se agrega la revista a la lista de termiandas aqui para evitar el bug
              #que cuando estas consultando y termina ok el ocr la 1ra vez te quita
              #la pagina de la lista (porque no entra en el elsif de abajo)
              @revistas_con_ocr.push revista

            else # Aun no ha terminado la tarea, o fallo, se mostrara su status
              if status == 'failed' # Si ya estaba marcada como failed
                progress = {}
                progress[:valid] = true
                progress[:status] = status
              else
                File.open("#{@@ruta}/#{revista}/ocr_progress","w") do |file| # Escribiendo nuevo porcentaje
                  file.puts id
                  file.puts progress[:status]
                  file.puts progress[:percent]
                  file.puts progress[:uptime]
                  file.puts progress[:outputs]
                  puts "Modificando el ocr_progress de la revista"
                end

              end

              @revistas_en_progreso[revista] = progress
            end # if status ... and :percent ... and :status ...
          
          else # Hubo un error al contactar al servicio cloud
            @revistas_en_progreso[revista] = progress # Se coloca para que salga con status N/D

          end # if status ... or progress ...

        # Si esta listo y la fecha de modificacion no ha pasado de max_seg_mostrar con respecto a ahorita, lo muestro
        elsif tiempo_ahora - File.mtime("#{@@ruta}/#{revista}/ocr_ready") < max_seg_mostrar
          @revistas_con_ocr.push revista
          
        end # if !File.exist? ... ocr_ready
      
      end # if !@@ignore_list.include? revista

    end # revistas.sort.each

  end # def

  def procesar_ocr
	rs = params[:revistas]
  
    if rs
      rs.each_value do |r| # r es cada revista seleccionada
        @in_imgs = Array.new()

        imagenes = Dir.open(File.join(@@ruta,r,"jpg"))

        imagenes.sort.each do |img|

          if !@@ignore_list.include? img then # Para evitar tomar archivos ignorados
            nombre=File.join(r,"jpg",File.basename(img))
            @in_imgs.push nombre
          end

        end

        # Es responsabilidad de la app crear la carpeta ocr, no del servicio nube
        
        FileUtils.mkdir("#{@@ruta}/#{r}/ocr") if !File.exist?("#{@@ruta}/#{r}/ocr") 

        # AQUI SE REALIZA LA LLAMADA AL SERVICIO CLOUD

        request = RestClient.post('http://localhost:9173/jobs',
            {:job => {
                'action' => 'tesseract_ocr',
                'inputs' => @in_imgs,
                'options' => {
                    'batch_size' => 1
                }
            }.to_json}
        )
  
        #Se crea el archivo para monitorear el progreso del job
        #solo es necesario el id y el progreso inicial
        
        #Cada vez que se llame al ocr se creara este archivo dentro de la revista
        #Porque si un archivo progress queda con status failed el mismo no podra ser 
        #sobreescrito y siempre aparecera la revista con fallida.
          request = JSON.parse(request)
          File.open("#{@@ruta}/#{r}/ocr_progress","w") do |file|
            file.puts request['id']
            file.puts request['percent_complete']
          end
        

        @in_imgs.clear

      end
	end

  end

  def job_progress(id)

    url = "http://localhost:9173/jobs/"+id.to_s

    result = {}

    begin # atrapar excepciones en caso de que el resource no exista
      job_representation = RestClient.get url
      puts "Resource con el get: "
      puts job_representation
      job_representation = JSON.parse(job_representation)
      result[:valid] = true
      result[:status] = job_representation['status']
      result[:percent] = job_representation['percent_complete']
      result[:uptime] = job_representation['time_taken']
      result[:outputs] = job_representation['outputs']
    rescue => e
      # esto puede ocurrir en caso que el server este abajo o el id del job ya no este disponible
      result[:valid] = false
    end

    result
  end

end

