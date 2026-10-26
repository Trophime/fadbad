fadbad++: 
	make -C examples CPPFLAGS="-I.."

check:	
	make -C test CPPFLAGS="-I.. -D_DEBUG"
	test/TestAll

clean:
	make -C examples clean
	make -C test clean

install:	
	mkdir -p $(DESTDIR)/usr/include/fadbad++
	mkdir -p $(DESTDIR)/usr/include/fadbad++/extra
	install -m 644 *.h $(DESTDIR)/usr/include/fadbad++
	install -m 644 extra/*.h $(DESTDIR)/usr/include/fadbad++/extra
	mkdir -p $(DESTDIR)/usr/share/fadbad++/examples
	install -m 644 examples/Makefile $(DESTDIR)/usr/share/fadbad++/examples
	install -m 644 examples/*.cpp $(DESTDIR)/usr/share/fadbad++/examples
	#install -m 644 examples/ExampleBAD $(DESTDIR)/usr/share/fadbad++/examples
	#install -m 644 examples/ExampleBADFAD[1234] $(DESTDIR)/usr/share/fadbad++/examples
	#install -m 644 examples/ExampleTAD[1234] $(DESTDIR)/usr/share/fadbad++/examples
	#install -m 644 examples/MonteCarlo $(DESTDIR)/usr/share/fadbad++/examples
	mkdir -p $(DESTDIR)/usr/share/fadbad++/test
	install -m 644 test/Makefile $(DESTDIR)/usr/share/fadbad++/test
	install -m 644 test/*.cpp $(DESTDIR)/usr/share/fadbad++/test
	install -m 644 test/*.h $(DESTDIR)/usr/share/fadbad++/test
	#install -m 644 test/TestAll $(DESTDIR)/usr/share/fadbad++/test
	
uninstall:	
	rm -rf $(DESTDIR)/usr/include/fadbad++
	rm -rf $(DESTDIR)/usr/share/fadbad++/examples
	rm -rf $(DESTDIR)/usr/share/fadbad++/test
	
