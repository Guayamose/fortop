require "open3"
require "securerandom"

module Scans
  class NodeSandbox
    # Only parse JavaScript; no package scripts, installs or repository code run.
    def initialize(image: ENV.fetch("SCAN_NODE_IMAGE", "node:24-bookworm-slim"))
      @image = image
    end

    def check(content)
      unless @image.match?(%r{\A[a-zA-Z0-9][a-zA-Z0-9_./:@-]{0,200}\z})
        return { "passed" => false, "details" => "SCAN_NODE_IMAGE no es una imagen válida." }
      end
      name = "fortop-syntax-#{SecureRandom.hex(8)}"
      result = nil
      # A literal executable plus individual argv values never invokes a shell.
      Open3.popen3("docker", "run", "--rm", "--name", name, "--pull=never", "--network=none", "--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges", "--pids-limit=32", "--memory=128m", "--cpus=0.5", "--user=65534:65534", "--tmpfs=/tmp:rw,noexec,nosuid,size=16m", "-i", @image, "node", "--check", "--input-type=module", pgroup: true) do |input, output, error, thread|
        input.write(content)
        input.close
        stdout = Thread.new { output.read(8192) }
        stderr = Thread.new { error.read(8192) }
        unless thread.join(20)
          Process.kill("TERM", -thread.pid) rescue nil
          result = { "passed" => false, "details" => "La verificación aislada de JavaScript ha agotado su tiempo." }
        else
          passed = thread.value.success?
          detail = stderr.value.to_s
          result = { "passed" => passed, "details" => passed ? "Sintaxis JavaScript comprobada en contenedor sin red; no se ejecutó código del repositorio." : "No se ha podido validar JavaScript en Docker: #{detail.truncate(700)}" }
        end
        stdout.kill if stdout.alive?
        stderr.kill if stderr.alive?
      end
      result
    rescue Errno::ENOENT, Errno::EPIPE, IOError
      { "passed" => false, "details" => "Docker o la imagen SCAN_NODE_IMAGE no están disponibles para validar JavaScript de forma aislada." }
    ensure
      if name
        # Clean up after timeout as well as normal --rm completion.
        system("docker", "rm", "-f", name, out: File::NULL, err: File::NULL)
      end
    end
  end
end
