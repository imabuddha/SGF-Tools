# See the ABOUT.txt file for the project description and brief directions for installation/use.

## Version history

* 1.2.4: 
    * Added 9 language localization string files using translations
	kindly supplied by Anders Kierulf (maker of the wonderful SmartGo
	software). Some are only partially translated.  Help with missing 
	translations & other languages welcomed!
	
* 1.2.3: 
    * Fixed bug that intermittently caused files to be only partially
	indexed by changing encoding to NSASCIIStringEncoding in do_property()

* 1.2.2: 
    * Added Year Played attr because for many old games only this part of
    the date is known. In contrast to the Date Played attr this one is
    a plain CFNumber.
 
    * Further improved the handling of DT prop to Date Played attr conv.
 
    * Replaced call to deprecated stringWithCString:length: in do_property()
    (I hate seeing warnings for a good build)
 
    * Added Winner & Loser attrs derrived from the RE PW PB props as
    suggested by Anders.
 
    * Fixed memory leaks in do_property() & appendString:forKey:

* 1.2.1: 
    * Within an hour of releasing 1.2 I found a bug in the DT code that
        caused the importer to crash on incomplete dates, this ver
        fixes that.
 
* 1.2:
    * First release that implemented "all" properties/attrs.

* 1.0.1:
    * Build as Intel 32/64 bit universal.
    
* 1.0:
    * Initial release.
    