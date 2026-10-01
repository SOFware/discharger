namespace :discharger do
  namespace :setup do
    desc "Fail when bin/setup differs from the installed discharger template"
    task :check, [:setup_path] do |_task, args|
      require "discharger/setup_check"
      abort unless Discharger::SetupCheck.run(args[:setup_path] || "bin/setup")
    end
  end
end
