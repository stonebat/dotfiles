# Set formula
formula = 'Google Chrome'

# Install package
dmg_package(formula) do
	dmg_name 'GoogleChrome'
	source 'http://dl.google.com/chrome/mac/dev/GoogleChrome.dmg'
end
