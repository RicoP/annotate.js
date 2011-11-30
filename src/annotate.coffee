#     Annotate - a text enhancement interaction jQuery UI widget
#     (c) 2011 Szaby Gruenwald, IKS Consortium
#     Annotate may be freely distributed under the MIT license

# define namespaces
ns =
    rdf:      'http://www.w3.org/1999/02/22-rdf-syntax-ns#'
    enhancer: 'http://fise.iks-project.eu/ontology/'
    dc:       'http://purl.org/dc/terms/'
    rdfs:     'http://www.w3.org/2000/01/rdf-schema#'
    skos:     'http://www.w3.org/2004/02/skos/core#'

vie = new VIE()
vie.use(new vie.StanbolService({
    url : "http://dev.iks-project.eu:8080",
    proxyDisabled: true
}));

# calling the get with a scope and callback will call cb(entity) with the scope as soon it's available.'
class EntityCache
    constructor: (opts) ->
        @vie = opts.vie
        @logger = opts.logger
    _entities: -> window.entityCache ?= {}
    get: (uri, scope, success, error) ->
        uri = uri.replace /^<|>$/g, ""
        # If entity is stored in the cache already just call cb
        if @_entities()[uri] and @_entities()[uri].status is "done"
            if typeof success is "function"
                success.apply scope, [@_entities()[uri].entity]
        else if @_entities()[uri] and @_entities()[uri].status is "error"
            if typeof error is "function"
                error.apply scope, ["error"]
        # If the entity is new to the cache
        else if not @_entities()[uri]
            # create cache entry
            @_entities()[uri] = 
                status: "pending"
                uri: uri
            cache = @
            # make a request to the entity hub
            @vie.load({entity: uri}).using('stanbol').execute().success (entityArr) =>
                _.defer =>
                    cacheEntry = @_entities()[uri]
                    entity = _.detect entityArr, (e) ->
                        true if e.getSubject() is "<#{uri}>"
                    if entity
                        cacheEntry.entity = entity
                        cacheEntry.status = "done"
                        $(cacheEntry).trigger "done", entity
                    else
                        @logger.warn "couldn''t load #{uri}", entityArr
                        cacheEntry.status = "not found"
            .fail (e) =>
                _.defer =>
                    @logger.error "couldn't load #{uri}"
                    cacheEntry = @_entities()[uri]
                    cacheEntry.status = "error"
                    $(cacheEntry).trigger "fail", e

        if @_entities()[uri] and @_entities()[uri].status is "pending"
            $( @_entities()[uri] )
            .bind "done", (event, entity) ->
                if typeof success is "function"
                    success.apply scope, [entity]
            .bind "fail", (event, error) ->
                if typeof error is "function"
                    error.apply scope, [error]

# Give back the last part of a uri for fallback label creation
uriSuffix = (uri) ->
    res = uri.substring uri.lastIndexOf("#") + 1
    res.substring res.lastIndexOf("/") + 1

######################################################
# Annotate widget
# makes a content dom element interactively annotatable
######################################################
jQuery.widget 'IKS.annotate',
    __widgetName: "IKS.annotate"
    options:
        # VIE instance to use for (backend) enhancement
        vie: vie
        vieServices: ["stanbol"]
        # Do analyze on instantiation
        autoAnalyze: false
        # Tooltip can be disabled
        showTooltip: true
        # Debug can be enabled
        debug: false
        # Define Entity properties for finding depiction
        depictionProperties: [
            "foaf:depiction"
            "schema:thumbnail"
        ]
        # Define Entity properties for finding the label
        labelProperties: [
            "rdfs:label"
            "skos:prefLabel"
            "schema:name"
            "foaf:name"
        ]
        # Define Entity properties for finding the description
        descriptionProperties: [
            "rdfs:comment"
            "skos:note"
            "schema:description"
            "skos:definition"
                property: "skos:broader"
                makeLabel: (propertyValueArr) ->
                    labels = _(propertyValueArr).map (termUri) ->
                        # extract the last part of the uri
                        termUri
                        .replace(/<.*[\/#](.*)>/, "$1")
                        .replace /_/g, "&nbsp;"
                    "Subcategory of #{labels.join ', '}."
            ,
                property: "dc:subject"
                makeLabel: (propertyValueArr) ->
                    labels = _(propertyValueArr).map (termUri) ->
                        # extract the last part of the uri
                        termUri
                        .replace(/<.*[\/#](.*)>/, "$1")
                        .replace /_/g, "&nbsp;"
                    "Subject(s): #{labels.join ', '}."
        ]
        # If label and description is not available in the user's language 
        # look for a fallback.
        fallbackLanguage: "en"
        # namespaces necessary for the widget configuration
        ns:
            dbpedia:  "http://dbpedia.org/ontology/"
            skos:     "http://www.w3.org/2004/02/skos/core#"
        # List of enhancement types to filter for
        typeFilter: null
        # Give a label to your expected enhancement types
        getTypes: ->
            [
                uri:   "#{@ns.dbpedia}Place"
                label: 'Place'
            ,
                uri:   "#{@ns.dbpedia}Person"
                label: 'Person'
            ,
                uri:   "#{@ns.dbpedia}Organisation"
                label: 'Organisation'
            ,
                uri:   "#{@ns.skos}Concept"
                label: 'Concept'
            ]
        # Give a label to the sources the entities come from
        getSources: ->
            [
                uri: "http://dbpedia.org/resource/"
                label: "dbpedia"
            ,
                uri: "http://sws.geonames.org/"
                label: "geonames"
            ]

    _create: ->
        widget = @
        # logger can be turned on and off. It will show the real caller line in the log
        @_logger = if @options.debug then console else 
            info: ->
            warn: ->
            error: ->
            log: ->
        # widget.entityCache.get(uri, cb) will get and cache the entity from an entityhub
        @entityCache = new EntityCache 
            vie: @options.vie
            logger: @_logger
        if @options.autoAnalyze
            @enable()
    _destroy: ->
        do @disable
        $( ':IKS-annotationSelector', @element ).each () ->
            $(@).annotationSelector 'destroy' if $(@).data().annotationSelector

    # analyze the widget element and show text enhancements
    enable: (cb) ->
        analyzedNode = @element
        # the analyzedDocUri makes the connection between a document state and
        # the annotations to it. We have to clean up the annotations to any
        # old document state

        @options.vie.analyze( element: @element ).using(@options.vieServices)
        .execute()
        .success (enhancements) =>
          _.defer =>
            # Link TextAnnotation entities to EntityAnnotations
            entityAnnotations = Stanbol.getEntityAnnotations(enhancements)
            for entAnn in entityAnnotations
                textAnns = entAnn.get "dc:relation"
                for textAnn in _.flatten([textAnns])
                    textAnn = entAnn.vie.entities.get textAnn unless textAnn instanceof Backbone.Model
                    continue unless textAnn
                    _(_.flatten([textAnn])).each (ta) ->
                        ta.setOrAdd
                            "entityAnnotation": entAnn.getSubject()
            # Get enhancements
            textAnnotations = Stanbol.getTextAnnotations(enhancements)
            textAnnotations = @_filterByType textAnnotations
            # Remove all textAnnotations without a selected text property
            textAnnotations = _(textAnnotations)
            .filter (textEnh) ->
                if textEnh.getSelectedText and textEnh.getSelectedText()
                    true
                else
                    false
            _(textAnnotations)
            .each (s) =>
                @_logger.info s._enhancement,
                    'confidence', s.getConfidence(),
                    'selectedText', s.getSelectedText(),
                    'type', s.getType(),
                    'EntityEnhancements', s.getEntityEnhancements()
                # Process the text enhancements
                @processTextEnhancement s, analyzedNode
            # trigger 'done' event with success = true
            @_trigger "success", true
            cb true if typeof cb is "function"
        .fail (xhr) =>
            cb false, xhr if typeof cb is "function"
            @_trigger 'error', xhr
            @_logger.error "analyze failed", xhr.responseText, xhr

    # Remove all not accepted text enhancement widgets
    disable: ->
        $( ':IKS-annotationSelector', @element ).each () ->
            $(@).annotationSelector 'disable' if $(@).data().annotationSelector

    # call `acceptBestCandidate` on each contained annotation selector
    acceptAll: (reportCallback) ->
        report = {updated: [], accepted: 0}
        $( ':IKS-annotationSelector', @element ).each () ->
            if $(@).data().annotationSelector
                res = $(@).annotationSelector 'acceptBestCandidate'
                if res
                    report.updated.push @
                    report.accepted++
        reportCallback? report

    # processTextEnhancement deals with one TextEnhancement in an ancestor element of its occurrence
    processTextEnhancement: (textEnh, parentEl) ->
        if not textEnh.getSelectedText()
            @_logger.warn "textEnh", textEnh, "doesn't have selected-text!"
            return
        el = $ @_getOrCreateDomElement parentEl[0], textEnh.getSelectedText(),
            createElement: 'span'
            createMode: 'existing'
            context: textEnh.getContext()
            start:   textEnh.getStart()
            end:     textEnh.getEnd()
        sType = textEnh.getType() or "Other"
        widget = @
        el.addClass('entity')
        for type in sType
            el.addClass uriSuffix(type).toLowerCase()
        if textEnh.getEntityEnhancements().length
            el.addClass "withSuggestions"
        for eEnh in textEnh.getEntityEnhancements()
            eEnhUri = eEnh.getUri()
            @entityCache.get eEnhUri, eEnh, (entity) =>
                if "<#{eEnhUri}>" is entity.getSubject()
                    @_logger.info "entity #{eEnhUri} is loaded:",
                        entity.as "JSON"
                else
                    widget._logger.info "forwarded entity for #{eEnhUri} loaded:", entity.getSubject()
        # Create widget to select from the suggested entities
        options = @options
        options.cache = @entityCache
        options.annotateElement = @element
        el.annotationSelector( options )
        .annotationSelector 'addTextEnhancement', textEnh

    _filterByType: (textAnnotations) ->
        return textAnnotations unless @options.typeFilter
        _.filter textAnnotations, (ta) =>
            return yes if @options.typeFilter in ta.getType()
            for type in @options.typeFilter
                return yes if type in ta.getType()

    # get or create a dom element containing only the occurrence of the found entity
    _getOrCreateDomElement: (element, text, options = {}) ->
        # Find occurrence indexes of s in str
        occurrences = (str, s) ->
            res = []
            last = 0
            while str.indexOf(s, last + 1) isnt -1
                next = str.indexOf s, last+1
                res.push next
                last = next

        # Find the nearest number among the 
        nearest = (arr, nr) ->
            _(arr).sortedIndex nr

        # Nearest position
        nearestPosition = (str, s, ind) ->
            arr = occurrences(str,s)
            i1 = nearest arr, ind
            if arr.length is 1
                arr[0]
            else if i1 is arr.length
                arr[i1-1]
            else
                i0 = i1-1
                d0 = ind - arr[i0]
                d1 = arr[i1] - ind
                if d1 > d0 then arr[i0]
                else arr[i1]

        domEl = element
        textContentOf = (element) -> $(element).text().replace(/\n/g, " ")
        # find the text node
        if textContentOf(element).indexOf(text) is -1
            console.error "'#{text}' doesn't appear in the text block."
            return $()
        start = options.start +
        textContentOf(element).indexOf textContentOf(element).trim()
        # Correct small position errors
        start = nearestPosition textContentOf(element), text, start
        pos = 0
        while textContentOf(domEl).indexOf(text) isnt -1 and domEl.nodeName isnt '#text'
            domEl = _(domEl.childNodes).detect (el) ->
                p = textContentOf(el).lastIndexOf text
                if p >= start - pos
                    true
                else
                    pos += textContentOf(el).length
                    false

        if options.createMode is "existing" and textContentOf($(domEl).parent()) is text
            return $(domEl).parent()[0]
        else
            pos = start - pos
            len = text.length
            textToCut = textContentOf(domEl).substring(pos, pos+len)
            if textToCut is text
                domEl.splitText pos + len
                newElement = document.createElement options.createElement or 'span'
                newElement.innerHTML = text
                $(domEl).parent()[0].replaceChild newElement, domEl.splitText pos
                $ newElement
            else
                console.warn "dom element creation problem: #{textToCut} isnt #{text}"

