import SwiftUI
import AppKit

struct ExtensionPlacement:LayoutValueKey {static let defaultValue:ExtensionWidget?=nil}
struct ExtensionGrid:Layout {
    private func metrics(_ proposal:ProposedViewSize,_ views:Subviews)->(CGFloat,[CGFloat],Int){
        let cols=max(1,views.map{v in let w=v[ExtensionPlacement.self];return min(1023,(w?.col ?? 1)+(w?.span ?? 1)-1)}.max() ?? 1)
        let hint=views.map{view in let w=view[ExtensionPlacement.self];return CGFloat(w?.width ?? 0)/CGFloat(max(1,w?.span ?? 1))}.max() ?? 0;let width=max(proposal.width ?? 620,max(30,hint)*CGFloat(cols)+CGFloat(cols-1)*12);let unit=max(30,(width-CGFloat(cols-1)*12)/CGFloat(cols));var rows=[CGFloat](repeating:0,count:max(1,views.map{v in let w=v[ExtensionPlacement.self];return (w?.row ?? 1)+(w?.rowspan ?? 1)-1}.max() ?? 1))
        for view in views{guard let w=view[ExtensionPlacement.self]else{continue};let span=min(w.span,cols-w.col+1);let size=view.sizeThatFits(ProposedViewSize(width:unit*CGFloat(span)+12*CGFloat(span-1),height:nil));let height=max(size.height,CGFloat(w.height));for row in (w.row-1)..<min(rows.count,w.row-1+w.rowspan){rows[row]=max(rows[row],(height-12*CGFloat(w.rowspan-1))/CGFloat(w.rowspan))}}
        return(unit,rows,cols)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize{let (unit,rows,cols)=metrics(proposal,subviews);return CGSize(width:unit*CGFloat(cols)+12*CGFloat(cols-1),height:rows.reduce(0,+)+12*CGFloat(rows.count-1))}
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()){let (unit,rows,cols)=metrics(ProposedViewSize(width:bounds.width,height:nil),subviews);for view in subviews{guard let w=view[ExtensionPlacement.self]else{continue};let span=min(w.span,cols-w.col+1);let width=unit*CGFloat(span)+12*CGFloat(span-1);let y=rows.prefix(w.row-1).reduce(0,+)+12*CGFloat(w.row-1);view.place(at:CGPoint(x:bounds.minX+(unit+12)*CGFloat(w.col-1),y:bounds.minY+y),anchor:.topLeading,proposal:ProposedViewSize(width:width,height:nil))}}
}
struct ExtensionTextInput:View {
    let widget:ExtensionWidget;let change:(String)->Void
    @State private var text="";@FocusState private var focused:Bool
    var body:some View{Group{if widget.kind=="password"{SecureField("",text:$text)}else{TextField("",text:$text)}}.textFieldStyle(.roundedBorder).focused($focused).onAppear{text=widget.text}.onChange(of:text){_,new in if new != widget.text{change(new)}}.onChange(of:widget.text){_,new in text=new}}
}
struct ExtensionHTML:NSViewRepresentable {
    let text:String
    func makeNSView(context:Context)->NSScrollView{let scroll=NSScrollView();let view=NSTextView();view.isEditable=false;view.isSelectable=true;view.drawsBackground=false;view.textContainerInset=NSSize(width:4,height:4);view.isVerticallyResizable=true;view.isHorizontallyResizable=false;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true;scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.documentView=view;return scroll}
    func updateNSView(_ view:NSScrollView,context:Context){guard let editor=view.documentView as? NSTextView else{return};let html="<style>body{font-family:-apple-system;font-size:13px;color:\(NSColor.labelColor.usingColorSpace(.deviceRGB).map{String(format:"#%02x%02x%02x",Int($0.redComponent*255),Int($0.greenComponent*255),Int($0.blueComponent*255))} ?? "#ffffff");}a{color:#ff9c48}</style>"+text
        if let data=html.data(using:.utf8),let value=try? NSAttributedString(data:data,options:[.documentType:NSAttributedString.DocumentType.html,.characterEncoding:String.Encoding.utf8.rawValue],documentAttributes:nil){if editor.attributedString() != value{editor.textStorage?.setAttributedString(value)}}else{editor.string=text}}
}

struct ExtensionSpinner:View {
    let widget:ExtensionWidget
    @State private var running=false
    var body:some View{Group{if running{ProgressView().controlSize(.small)}else{Image(systemName:"circle.dotted")}}.task(id:"\(widget.animationToken)-\(widget.animating)"){running=widget.animating;if running && widget.spinLoops>0{do{try await Task.sleep(nanoseconds:UInt64(min(86400,Double(widget.spinLoops)*0.8)*1e9));running=false}catch{}}}}
}

/// Native popup selection is committed before deferred extension button callbacks.
struct ExtensionPopup:NSViewRepresentable {
    let widget:ExtensionWidget;let register:(NSPopUpButton)->Void;let change:(Int)->Void
    final class Coordinator:NSObject{var change:(Int)->Void;init(_ change:@escaping(Int)->Void){self.change=change};@objc func selected(_ sender:NSPopUpButton){change(sender.selectedItem?.tag ?? -1)}}
    func makeCoordinator()->Coordinator{Coordinator(change)}
    func makeNSView(context:Context)->NSPopUpButton{let button=NSPopUpButton(frame:.zero,pullsDown:false);button.target=context.coordinator;button.action=#selector(Coordinator.selected(_:));button.controlSize = .regular;return button}
    func updateNSView(_ button:NSPopUpButton,context:Context){context.coordinator.change=change;register(button);if button.itemTitles != widget.values.map(\.text) || button.itemArray.map(\.tag) != widget.values.map(\.id){button.removeAllItems();for choice in widget.values{button.addItem(withTitle:choice.text);button.lastItem?.tag=choice.id}};if let index=widget.values.firstIndex(where:{$0.id==widget.value}){if button.indexOfSelectedItem != index{button.selectItem(at:index)}}else{button.select(nil)};button.isEnabled=widget.enabled}
}
