require 'xcodeproj'
project_path = 'MartenIOSWrapper.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Add SelectSinglePinboardIntent to App and Widget targets
app_target = project.targets.find { |t| t.name == 'MartenIOSWrapper' || t.name == 'Marten' } # Main app
widget_target = project.targets.find { |t| t.name == 'MartenWidgetsExtension' }

app_group = project.main_group.find_subpath(File.join('..', 'MartenIOS', 'Sources', 'MartenIOSApp', 'Integrations'), true)
file_ref = app_group.new_reference('../MartenIOS/Sources/MartenIOSApp/Integrations/SelectSinglePinboardIntent.swift')

if app_target
  app_target.source_build_phase.add_file_reference(file_ref)
end
if widget_target
  widget_target.source_build_phase.add_file_reference(file_ref)
end

project.save
