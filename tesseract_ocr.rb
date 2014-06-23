require 'net/scp'
require 'active_record'
require 'yaml'

class Pagina < ActiveRecord::Base
end

Pagina.establish_connection(
 :adapter=>CloudCrowd.config[:activerecord_adapter],
 :database=>CloudCrowd.config[:activerecord_db],
 :host=>CloudCrowd.config[:activerecord_host],
 :login=>CloudCrowd.config[:activerecord_login],
 :password=>CloudCrowd.config[:activerecord_password]
)

# A parallel OCR tool. Depends on 'tesseract' OCR software and net-scp gem.
class TesseractOcr < CloudCrowd::Action

  #def split
   # input.each do |entrada|
   #   puts input
   # end
  #end



  # Process an image for OCR and upload the resulting HOCR into server
  def process
    puts input
    arr = input.split(File::SEPARATOR).last(3)
    revista = arr.first
    in_filename = arr.last
    output={}
    ti = 0
    tm = 0
    ok = false

    Net::SCP.start(CloudCrowd.config[:scp_host], CloudCrowd.config[:scp_user], :password => CloudCrowd.config[:scp_password]) do |scp|
        scp.download!(File.join(CloudCrowd.config[:scp_workdir],input), in_filename)

        #out_filename = File.basename(in_filename, File.extname(in_filename)) + ".hocr"
        #out_filename = in_filename + ".hocr"

        ti = Time.now
        ok = system("tesseract #{in_filename} #{in_filename} -l spa -o hocr") # Tesseract appends .html to output filename
        tm = Time.now

        puts "Tiempo de procesamiento de la pagina (OCR): " + (tm-ti).to_s

        out_filename = in_filename + ".hocr"
        up_dir = File.join(CloudCrowd.config[:scp_workdir],File.split(input)[0],"../ocr",out_filename)
        #up_dir = File.join(CloudCrowd.config[:scp_workdir],File.split(input)[0],"ocr",out_filename)

        #puts "in: '#{in_filename}.html' up: '#{up_dir}' dir: '#{Dir.glob("*").join(",")}'"

        scp.upload!(in_filename + ".html", up_dir)
        
    end

    if ok
      #begin
        p = Pagina.first(:conditions => {
                             :ruta_de_la_pagina => "public//files//#{revista}//jpg//#{in_filename}"
                           }
                        )
        
        if !p.nil?
          #p.flag_ocr=1
          p.seg = tm-ti
          p.save
          puts ". SAVED!"
        else
          puts ". NOT SAVED"
        end
        
        #Objeto output para el Worker que se enviara al Merge
        output[:revista]=revista
        output[:status]=true
        output[:pagina]=in_filename
        
        
    else
      #Objeto output para el Worker que se enviara al Merge
        output[:revista]=revista
        output[:status]=false
        output[:pagina]=in_filename
    end
    output = YAML::dump(output) #Serializacion con YAML
    return output

end

def merge
  flag=true
  revista=""
  i=1
  input.each do |result|
    result=YAML::load(result) #Deserializacion con YAML
    if i=1
      revista=result[:revista] #la asignacion solo la hago con el primer result no tiene sentido sobreescribirla
    end
    if result[:status]=false #si alguno fue false ya no se escribira el ocr_ready
      flag=false
    end
    i+=1
    
  end  
 
  if flag
    Net::SCP.start(CloudCrowd.config[:scp_host], CloudCrowd.config[:scp_user], :password => CloudCrowd.config[:scp_password]) do |scp|
      if !File.exist?("ocr_ready") #Como el merge lo haran varios jobs dentro del mismo Dir puede que alguno ya haya creado el archivo
      File.open("ocr_ready","w") #solo se crea para poderlo subir al server con scp
      end
      up_dir = File.join(CloudCrowd.config[:scp_workdir],revista)
      scp.upload!("ocr_ready", up_dir)
      
    end
  end
  
end

end
